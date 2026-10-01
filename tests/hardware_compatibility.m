// Exercise the real topology validation and CPU sampler with deterministic hardware inputs.
#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import <mach/mach.h>
#import <mach/processor_info.h>
#import <IOKit/IOKitLib.h>
static int pCount = 4, eCount = 6, levelCount = 2;
static BOOL reverseLevels = NO;
static NSString *chip = @"Apple M4";
static NSArray *coreRows;
static uint32_t counters[64][CPU_STATE_MAX];
static int mockSysctl(const char *key, void *value, size_t *size, void *newValue, size_t newSize) {
    NSString *name = @(key); id result = nil;
    if ([name isEqual:@"hw.logicalcpu"]) result = @(pCount + eCount);
    else if ([name isEqual:@"hw.nperflevels"]) result = @(levelCount);
    else if ([name isEqual:@"machdep.cpu.brand_string"]) result = chip;
    for (int i = 0; i < 2; i++) {
        BOOL performance = reverseLevels ? i == 1 : i == 0;
        if ([name isEqual:[NSString stringWithFormat:@"hw.perflevel%d.name", i]]) result = performance ? @"Performance" : @"Efficiency";
        if ([name isEqual:[NSString stringWithFormat:@"hw.perflevel%d.logicalcpu", i]]) result = @(performance ? pCount : eCount);
    }
    if (!result) return sysctlbyname(key, value, size, newValue, newSize);
    if ([result isKindOfClass:NSString.class]) {
        const char *text = [result UTF8String]; size_t length = strlen(text) + 1;
        if (*size < length) return -1;
        memcpy(value, text, length); *size = length;
    } else { if (*size < sizeof(int)) return -1; *(int *)value = [result intValue]; *size = sizeof(int); }
    return 0;
}
static kern_return_t mockCPU(host_t host, processor_flavor_t flavor, natural_t *count,
                            processor_info_array_t *info, mach_msg_type_number_t *words) {
    *count = pCount + eCount; *words = *count * CPU_STATE_MAX;
    vm_address_t address = 0;
    kern_return_t result = vm_allocate(mach_task_self(), &address, *words * sizeof(integer_t), VM_FLAGS_ANYWHERE);
    if (result != KERN_SUCCESS) return result;
    *info = (processor_info_array_t)address;
    memcpy(*info, counters, *words * sizeof(integer_t)); return KERN_SUCCESS;
}
static NSDictionary *sensors = nil;
static BOOL mockSMC = NO;
static int infoReads, valueReads;
static kern_return_t mockConnect(mach_port_t, uint32_t, const void *, size_t, void *, size_t *);
#define sysctlbyname mockSysctl
#define host_processor_info mockCPU
#define IOConnectCallStructMethod mockConnect
#import "../app/TelemetryBackend.m"
#undef sysctlbyname
#undef host_processor_info
#undef IOConnectCallStructMethod

static kern_return_t mockConnect(mach_port_t connection, uint32_t selector, const void *input,
                                size_t inputSize, void *output, size_t *outputSize) {
    if (!mockSMC) return IOConnectCallStructMethod(connection, selector, input, inputSize, output, outputSize);
    const SMCRequest *request = input; SMCRequest *response = output;
    memset(response, 0, sizeof(*response));
    NSDictionary *sensor = sensors[@(request->key)];
    if (!sensor) { response->result = 1; return KERN_SUCCESS; }
    if (request->command == 9) {
        infoReads++; response->info.size = [sensor[@"size"] unsignedIntValue];
        response->info.type = fourcc([sensor[@"type"] UTF8String]);
    } else if (request->command == 5) {
        valueReads++;
        if ([sensor[@"fail"] boolValue]) return KERN_FAILURE;
        if ([sensor[@"type"] isEqual:@"sp78"]) {
            int16_t value = [sensor[@"value"] doubleValue] * 256;
            response->bytes[0] = (uint16_t)value >> 8; response->bytes[1] = value & 255;
        } else { float value = [sensor[@"value"] floatValue]; memcpy(response->bytes, &value, 4); }
    } else return KERN_INVALID_ARGUMENT;
    return KERN_SUCCESS;
}
static int assertions;
#define CHECK(condition) do { assertions++; if (!(condition)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); exit(1); } } while (0)
static BOOL measured(NSDictionary *value) { return [value[@"status"] isEqual:@"measured"]; }

@interface TelemetryBackend (CompatibilityChecks)
- (NSDictionary *)nextCPU;
- (void)temperatureChecks;
@end
@implementation TelemetryBackend (CompatibilityChecks)
- (NSDictionary *)nextCPU { _cpuTime = monotonic() - 2; return [self cpu]; }
- (void)temperatureChecks {
    io_connect_t saved = _smc; _smc = 1; mockSMC = YES;
    for (NSString *family in @[@"Apple M1 Max", @"Apple M2", @"Apple M3 Pro", @"Apple M4", @"Apple M4 Max"]) {
        NSString *wanted = [family containsString:@"M1"] ? @"Tg05" : [family containsString:@"M2"] ? @"Tg0f" :
            [family containsString:@"M3"] ? @"Tf14" : [family containsString:@"Max"] ? @"Tg1U" : @"Tg0G";
        sensors = @{ @(fourcc(wanted.UTF8String)): @{ @"size": @4, @"type": @"flt ", @"value": @52.5 } };
        TemperatureSensor sensor = {0}; infoReads = valueReads = 0;
        [self selectTemperature:&sensor keys:temperatureKeys(family, YES)];
        CHECK(!strcmp(sensor.key, wanted.UTF8String));
        CHECK(infoReads == 1 && valueReads == 1);
        for (int i = 0; i < 5; i++) {
            NSDictionary *value = [self temperature:&sensor];
            CHECK(measured(value)); CHECK([value[@"value"] doubleValue] == 52.5);
        }
        CHECK(infoReads == 1 && valueReads == 6); // Selection and metadata stay cached.
        sensors = @{}; CHECK([self temperature:&sensor][@"value"] == nil);
    }
    // A zero, invalid encoding, or NaN cannot win selection over a working fallback.
    sensors = @{ @(fourcc("Tg0G")): @{ @"size": @4, @"type": @"flt ", @"value": @0 },
                 @(fourcc("Tg0H")): @{ @"size": @4, @"type": @"ui32", @"value": @50 },
                 @(fourcc("Tg1U")): @{ @"size": @4, @"type": @"flt ", @"value": @(NAN) },
                 @(fourcc("Tg0K")): @{ @"size": @2, @"type": @"sp78", @"value": @48.25 } };
    TemperatureSensor sensor = {0}; [self selectTemperature:&sensor keys:temperatureKeys(@"Apple M4", YES)];
    CHECK(!strcmp(sensor.key, "Tg0K")); CHECK([self temperature:&sensor][@"value"] != nil);
    sensors = @{}; [self selectTemperature:&sensor keys:temperatureKeys(@"Apple M4", YES)];
    CHECK(!sensor.key[0] && [self temperature:&sensor][@"value"] == nil);
    CHECK(temperatureKeys(@"Apple unknown", YES).count == 0);
    CHECK([temperatureKeys(@"Apple M3 Max", NO).firstObject isEqual:@"Tf04"]);
    mockSMC = NO; _smc = saved;
}
@end

@interface FixtureBackend : TelemetryBackend
@end
@implementation FixtureBackend
- (NSArray *)readCPUCores { return coreRows; }
@end

static NSArray *rows(int performance, int efficiency, BOOL interleaved) {
    NSMutableArray *result = [NSMutableArray array]; int total = performance + efficiency;
    // Shuffled registry iteration and non-contiguous P/E indices must still group correctly.
    for (int i = total - 1; i >= 0; i--) {
        BOOL p = interleaved ? i % 2 == 0 : i >= efficiency;
        [result addObject:@{ @"id": @(i), @"kind": p ? @"P" : @"E" }];
    }
    return result;
}
static void usageChecks(void) {
    memset(counters, 0, sizeof(counters));
    FixtureBackend *backend = [FixtureBackend new];
    CHECK([backend.capabilities[@"topology"] isEqual:@"measured"]);
    CHECK(backend.capabilities[@"performanceCores"].intValue == pCount);
    CHECK(backend.capabilities[@"efficiencyCores"].intValue == eCount);
    for (NSDictionary *core in coreRows) {
        int i = [core[@"id"] intValue]; BOOL p = [core[@"kind"] isEqual:@"P"];
        counters[i][CPU_STATE_USER] = p ? 80 : 10;
        counters[i][CPU_STATE_IDLE] = p ? 20 : 90;
    }
    NSDictionary *value = [backend nextCPU];
    CHECK(measured(value[@"p"]) && measured(value[@"e"]));
    CHECK(fabs([value[@"p"][@"value"] doubleValue] - 0.8) < 1e-9);
    CHECK(fabs([value[@"e"][@"value"] doubleValue] - 0.1) < 1e-9);
    CHECK(fabs([value[@"total"][@"value"] doubleValue] - (0.8 * pCount + 0.1 * eCount) / (pCount + eCount)) < 1e-9);
    [backend shutdown];
}
int main(void) { @autoreleasepool {
    setenv("COMPUTE_MONITOR_NETWORK_DISABLED", "1", 1);
    const int layouts[][2] = { {4,4}, {6,2}, {8,2}, {8,4}, {12,4}, {16,4}, {16,8}, {24,8}, {4,6}, {10,4}, {12,6} };
    for (NSUInteger i = 0; i < sizeof(layouts)/sizeof(layouts[0]); i++) {
        pCount = layouts[i][0]; eCount = layouts[i][1];
        coreRows = rows(pCount, eCount, NO); reverseLevels = i % 2;
        usageChecks();
    }
    pCount = eCount = 4; coreRows = rows(4, 4, YES); usageChecks();
    CPUTopology topology;
    NSMutableArray *bad = [coreRows mutableCopy]; bad[0] = bad[1];
    CHECK(!makeTopology(bad, 8, 4, 4, &topology));
    bad = [coreRows mutableCopy]; [bad removeLastObject]; CHECK(!makeTopology(bad, 8, 4, 4, &topology));
    for (id index in @[@(-1), @8, @0.5, @"0"]) {
        bad = [coreRows mutableCopy]; bad[0] = @{ @"id": index, @"kind": @"P" };
        CHECK(!makeTopology(bad, 8, 4, 4, &topology));
    }
    bad = [coreRows mutableCopy]; bad[0] = @{ @"id": @7, @"kind": @"unknown" };
    CHECK(!makeTopology(bad, 8, 4, 4, &topology));
    CHECK(!makeTopology(coreRows, 8, 6, 2, &topology));
    CHECK(!makeTopology(@[], 65, 64, 1, &topology));
    CHECK(!makeTopology(coreRows, 8, 8, 0, &topology));
    CHECK([coreKind((__bridge CFTypeRef)[NSData dataWithBytes:"P\0" length:2]) isEqual:@"P"]);
    CHECK(coreKind((__bridge CFTypeRef)[NSData dataWithBytes:"Performance" length:11]) == nil);
    // A failed topology still permits total CPU; P/E must not be fabricated.
    coreRows = bad; memset(counters, 0, sizeof(counters));
    FixtureBackend *backend = [FixtureBackend new];
    CHECK([backend.capabilities[@"topology"] isEqual:@"unavailable"]);
    for (int i = 0; i < 8; i++) { counters[i][CPU_STATE_USER] = 50; counters[i][CPU_STATE_IDLE] = 50; }
    NSDictionary *value = [backend nextCPU];
    CHECK(measured(value[@"total"])); CHECK(value[@"p"][@"value"] == nil && value[@"e"][@"value"] == nil);
    [backend temperatureChecks]; [backend shutdown];
    levelCount = 3; coreRows = rows(4, 4, NO); backend = [FixtureBackend new];
    CHECK([backend.capabilities[@"topology"] isEqual:@"unavailable"]); [backend shutdown];
    printf("HARDWARE_COMPATIBILITY PASS layouts=12 assertions=%d\n", assertions);
    return 0;
} }

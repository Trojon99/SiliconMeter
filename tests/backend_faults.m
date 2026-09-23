// Compile the real implementation with deterministic system-call/IOReport seams.
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach/processor_info.h>
#import <IOKit/IOKitLib.h>
static kern_return_t testConnect(mach_port_t, uint32_t, const void *, size_t, void *, size_t *);
static BOOL failVM = NO, failCPU = NO;
static uint32_t cpuCounter = 100;
static kern_return_t testVM(host_t host, host_flavor_t flavor, host_info64_t info, mach_msg_type_number_t *count) {
    if (failVM) return KERN_FAILURE;
    memset(info, 0, *count * sizeof(integer_t));
    ((vm_statistics64_t)info)->swapins = 200;
    ((vm_statistics64_t)info)->swapouts = 400;
    return KERN_SUCCESS;
}
static kern_return_t testCPU(host_t host, processor_flavor_t flavor, natural_t *count,
                             processor_info_array_t *info, mach_msg_type_number_t *words) {
    if (failCPU) return KERN_FAILURE;
    *count = 10; *words = 10 * CPU_STATE_MAX;
    vm_address_t address = 0;
    kern_return_t kr = vm_allocate(mach_task_self(), &address, *words * sizeof(integer_t), VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) return kr;
    *info = (processor_info_array_t)address;
    for (unsigned i = 0; i < *words; i++) (*info)[i] = cpuCounter;
    return KERN_SUCCESS;
}
#define IOConnectCallStructMethod testConnect
#define host_statistics64 testVM
#define host_processor_info testCPU
#import "../app/TelemetryBackend.m"
#undef host_statistics64
#undef host_processor_info
#undef IOConnectCallStructMethod

static BOOL mockSMC = NO, failSMC = NO;
static int smcInfoReads = 0, smcValueReads = 0, smcUnexpectedKeys = 0;
static kern_return_t testConnect(mach_port_t connection, uint32_t selector, const void *input, size_t inputSize, void *output, size_t *outputSize) {
    if (!mockSMC) return IOConnectCallStructMethod(connection, selector, input, inputSize, output, outputSize);
    const SMCRequest *request = input; SMCRequest *response = output;
    memset(response, 0, sizeof(*response));
    if (request->key != fourcc("Tp05") && request->key != fourcc("Tg05")) smcUnexpectedKeys++;
    if (request->command == 9) {
        smcInfoReads++; response->info.size = 4; response->info.type = fourcc("flt ");
    } else if (request->command == 5) {
        smcValueReads++;
        if (failSMC) return KERN_FAILURE;
        float temperature = 52.5; memcpy(response->bytes, &temperature, 4);
    } else return KERN_INVALID_ARGUMENT;
    return KERN_SUCCESS;
}
static int assertions = 0;
#define CHECK(test) do { assertions++; if (!(test)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #test); exit(1); } } while (0)
static BOOL status(NSDictionary *value, NSString *wanted) { return [value[@"status"] isEqual:wanted]; }
static BOOL sampleFails = NO, deltaFails = NO;
static NSDictionary *fixture;
static CFDictionaryRef fakeSample(IRSubscription sub, CFMutableDictionaryRef channels, CFTypeRef arg) {
    return sampleFails ? NULL : CFBridgingRetain(@{});
}
static CFDictionaryRef fakeDelta(CFDictionaryRef previous, CFDictionaryRef current, CFTypeRef arg) {
    return deltaFails ? NULL : CFBridgingRetain(fixture);
}
static CFStringRef fakeName(CFDictionaryRef item) { return CFDictionaryGetValue(item, CFSTR("name")); }
static CFStringRef fakeUnit(CFDictionaryRef item) { return CFDictionaryGetValue(item, CFSTR("unit")); }
static int64_t fakeInteger(CFDictionaryRef item, void *unused) { return [((__bridge NSDictionary *)item)[@"n"] longLongValue]; }
static int32_t fakeCount(CFDictionaryRef item) { return (int32_t)[((__bridge NSDictionary *)item)[@"states"] count]; }
static CFStringRef fakeState(CFDictionaryRef item, int32_t i) {
    return (__bridge CFStringRef)((__bridge NSDictionary *)item)[@"states"][i][@"name"];
}
static int64_t fakeResidency(CFDictionaryRef item, int32_t i) {
    return [((__bridge NSDictionary *)item)[@"states"][i][@"n"] longLongValue];
}
static void energy(int64_t n, NSString *unit) {
    fixture = @{ @"IOReportChannels": @[ @{ @"name": @"GPU Energy", @"unit": unit, @"n": @(n) } ] };
}
static void baseline(IRChannel *channel, double age) {
    if (channel->previous) CFRelease(channel->previous);
    channel->previous = CFBridgingRetain(@{});
    channel->previousTime = monotonic() - age;
}

@implementation TelemetryBackend (FaultChecks)
- (void)runFaultChecks {
    io_connect_t savedSMC = _smc;
    _smc = 1; mockSMC = YES; _tpChecked = NO; _tgChecked = NO;
    for (int i = 0; i < 12; i++) {
        CHECK(status([self smc:"Tp05" size:&_tpSize type:&_tpType checked:&_tpChecked], @"measured"));
        CHECK(status([self smc:"Tg05" size:&_tgSize type:&_tgType checked:&_tgChecked], @"measured"));
    }
    CHECK(smcInfoReads == 2); CHECK(smcValueReads == 24); CHECK(smcUnexpectedKeys == 0);
    failSMC = YES;
    CHECK(status([self smc:"Tp05" size:&_tpSize type:&_tpType checked:&_tpChecked], @"invalid"));
    failSMC = NO;
    CHECK(status([self smc:"Tp05" size:&_tpSize type:&_tpType checked:&_tpChecked], @"measured"));
    CHECK(smcInfoReads == 2);
    mockSMC = NO; _smc = savedSMC;
    failVM = YES;
    NSDictionary *v = [self sampleSlow];
    for (NSString *key in @[@"free", @"active", @"inactive", @"wired", @"compressed", @"swapIn", @"swapOut"]) {
        CHECK(status(v[key], @"invalid")); CHECK(v[key][@"value"] == nil);
    }
    CHECK(status(v[@"physical"], @"measured"));
    failVM = NO;
    CHECK(status([self vm][@"swapIn"], @"unavailable"));
    _vmTime = monotonic() - 6.2; _swapIn = 100; _swapOut = 200;
    v = [self vm];
    CHECK(fabs([v[@"swapIn"][@"value"] doubleValue] * [v[@"swapIn"][@"window_s"] doubleValue] - 100) < 1e-8);
    _swapIn = 300;
    CHECK(status([self vm][@"swapIn"], @"unavailable"));
    _vmTime = monotonic() - 31;
    CHECK(status([self vm][@"swapIn"], @"unavailable"));

    failCPU = YES;
    CHECK(status([self cpu][@"total"], @"invalid"));
    failCPU = NO; cpuCounter += 100;
    CHECK(status([self cpu][@"total"], @"unavailable"));
    cpuCounter += 100; _topologyValid = NO;
    v = [self cpu];
    CHECK(status(v[@"total"], @"measured"));
    CHECK(status(v[@"p"], @"unavailable")); CHECK(status(v[@"e"], @"unavailable"));
    cpuCounter = 1;
    CHECK(status([self cpu][@"total"], @"unavailable"));
    cpuCounter += 100;
    CHECK(status([self cpu][@"total"], @"measured"));
    for (int i = 0; i < 10; i++) for (int j = 0; j < CPU_STATE_MAX; j++) _ticks[i][j] = UINT32_MAX - 5;
    cpuCounter = 5;
    CHECK(status([self cpu][@"total"], @"measured"));
    _cpuTime = monotonic() - 31; cpuCounter += 100;
    CHECK(status([self cpu][@"total"], @"unavailable"));

    IRAPI saved = _ir;
    _ir.sample = fakeSample; _ir.delta = fakeDelta; _ir.name = fakeName; _ir.unit = fakeUnit;
    _ir.integer = fakeInteger; _ir.count = fakeCount; _ir.stateName = fakeState; _ir.residency = fakeResidency;
    IRChannel channel = {0};
    channel.subscription = (void *)1;
    channel.channels = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    energy(31000000000LL, @"nJ"); baseline(&channel, 6.2);
    v = [self sampleChannel:&channel gpu:NO];
    CHECK(status(v, @"estimated"));
    CHECK(fabs([v[@"value"] doubleValue] * [v[@"window_s"] doubleValue] - 31) < 1e-8);
    CHECK([v[@"value"] doubleValue] > 4.9 && [v[@"value"] doubleValue] <= 5.0);
    sampleFails = YES;
    CHECK(status([self sampleChannel:&channel gpu:NO], @"invalid")); CHECK(channel.previous == NULL);
    sampleFails = NO;
    CHECK(status([self sampleChannel:&channel gpu:NO], @"unavailable")); CHECK(channel.previous != NULL);
    baseline(&channel, 6.2);
    CHECK(status([self sampleChannel:&channel gpu:NO], @"estimated"));
    baseline(&channel, 31);
    CHECK(status([self sampleChannel:&channel gpu:NO], @"stale"));
    baseline(&channel, 2); deltaFails = YES;
    CHECK(status([self sampleChannel:&channel gpu:NO], @"invalid")); CHECK(channel.previous == NULL);
    deltaFails = NO;
    for (NSNumber *bad in @[@(-1), @(INT64_MIN), @(INT64_MAX)]) {
        energy(bad.longLongValue, @"nJ"); baseline(&channel, 2);
        v = [self sampleChannel:&channel gpu:NO];
        CHECK(status(v, @"invalid")); CHECK(v[@"value"] == nil); CHECK(channel.previous == NULL);
    }
    energy(100, @"mJ"); baseline(&channel, 2);
    CHECK(status([self sampleChannel:&channel gpu:NO], @"invalid"));
    fixture = @{ @"IOReportChannels": @[@{}, @{}] }; baseline(&channel, 2);
    CHECK(status([self sampleChannel:&channel gpu:NO], @"invalid"));
    energy(0, @"nJ"); baseline(&channel, 2);
    v = [self sampleChannel:&channel gpu:NO];
    CHECK(status(v, @"estimated")); CHECK([v[@"value"] doubleValue] == 0);

    _gpuFrequencies = @[@0, @400, @600];
    NSMutableArray *states = [NSMutableArray array];
    for (int i = 0; i < 16; i++) [states addObject:@{ @"name": i ? [NSString stringWithFormat:@"P%d", i] : @"OFF", @"n": @(i < 2 ? 100 : 0) }];
    fixture = @{ @"IOReportChannels": @[@{ @"name": @"GPUPH", @"unit": @"24Mticks", @"states": states }] };
    baseline(&channel, 2); v = [self sampleChannel:&channel gpu:YES];
    CHECK(status(v[@"active"], @"measured")); CHECK([v[@"active"][@"value"] doubleValue] == 0.5);
    CHECK(status(v[@"frequency"], @"estimated")); CHECK([v[@"frequency"][@"value"] doubleValue] == 400);
    states[1] = @{ @"name": @"P1", @"n": @0 };
    baseline(&channel, 2); v = [self sampleChannel:&channel gpu:YES];
    CHECK([v[@"active"][@"value"] doubleValue] == 0);
    CHECK(status(v[@"frequency"], @"unavailable")); CHECK(v[@"frequency"][@"value"] == nil);
    states[15] = @{ @"name": @"P15", @"n": @1 };
    baseline(&channel, 2); CHECK(status([self sampleChannel:&channel gpu:YES], @"invalid"));
    states[15] = @{ @"name": @"P15", @"n": @(INT64_MIN) };
    baseline(&channel, 2); CHECK(status([self sampleChannel:&channel gpu:YES], @"invalid"));
    states[15] = @{ @"name": @"P14", @"n": @0 };
    baseline(&channel, 2); CHECK(status([self sampleChannel:&channel gpu:YES], @"invalid"));
    if (channel.previous) CFRelease(channel.previous);
    CFRelease(channel.channels);
    _ir = saved;
}
@end

int main(void) { @autoreleasepool {
    TelemetryBackend *backend = [TelemetryBackend new];
    [backend runFaultChecks];
    [backend shutdown]; [backend shutdown];
    printf("BACKEND_FAULTS PASS assertions=%d\n", assertions);
    return 0;
} }

#import "TelemetryBackend.h"
#import "NetworkSampler.h"
#import <IOKit/IOKitLib.h>
#import <mach/mach.h>
#import <mach/processor_info.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <time.h>
#import <math.h>
#ifdef STEP31_REVIEW
#import <libproc.h>
#import <sys/resource.h>
#endif

// The private ABI and ownership rules here are based on the validated Step 2.6 probe.
typedef void *IRSubscription;
typedef CFMutableDictionaryRef (*IRCopy)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
typedef IRSubscription (*IRSubscribe)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*IRSample)(IRSubscription, CFMutableDictionaryRef, CFTypeRef);
typedef CFDictionaryRef (*IRDelta)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
typedef CFStringRef (*IRString)(CFDictionaryRef);
typedef int64_t (*IRInteger)(CFDictionaryRef, void *);
typedef int32_t (*IRCount)(CFDictionaryRef);
typedef CFStringRef (*IRStateName)(CFDictionaryRef, int32_t);
typedef int64_t (*IRResidency)(CFDictionaryRef, int32_t);
typedef struct {
    void *handle;
    IRCopy copy; IRSubscribe subscribe; IRSample sample; IRDelta delta;
    IRString name, unit; IRInteger integer; IRCount count;
    IRStateName stateName; IRResidency residency;
} IRAPI;
typedef struct {
    IRSubscription subscription;
    CFMutableDictionaryRef channels;
    CFDictionaryRef previous;
    double previousTime;
    BOOL ready;
} IRChannel;

typedef struct { char major,minor,build,reserved; uint16_t release; } SMCVers;
typedef struct { uint16_t version,length; uint32_t cpu,gpu,mem; } SMCLimit;
typedef struct { uint32_t size,type; uint8_t attributes; } SMCInfo;
typedef struct { uint32_t key; SMCVers vers; SMCLimit limit; SMCInfo info;
    uint8_t result,status,command; uint32_t data32; uint8_t bytes[32]; } SMCRequest;

static double monotonic(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}
static NSDictionary *reading(id value, NSString *unit, NSString *status, NSString *source,
                             double window, NSString *reason) {
    NSMutableDictionary *m = [@{ @"status": status, @"source": source, @"unit": unit } mutableCopy];
    if (value) m[@"value"] = value;
    if (window > 0 && isfinite(window)) m[@"window_s"] = @(window);
    if (reason) m[@"reason"] = reason;
    return m;
}
static NSDictionary *missing(NSString *status, NSString *source, NSString *reason) {
    return reading(nil, @"", status, source, 0, reason);
}
static int sysInt(const char *key) {
    int value = 0; size_t n = sizeof(value);
    return sysctlbyname(key, &value, &n, NULL, 0) == 0 && n == sizeof(value) ? value : -1;
}
static NSString *sysText(const char *key) {
    char value[128] = {0}; size_t n = sizeof(value);
    if (sysctlbyname(key, value, &n, NULL, 0) || !n || n > sizeof(value) || value[n - 1]) return nil;
    return [NSString stringWithUTF8String:value];
}
static NSString *coreKind(CFTypeRef value) {
    if (!value || CFGetTypeID(value) != CFDataGetTypeID()) return nil;
    CFIndex n = CFDataGetLength(value);
    const UInt8 *bytes = CFDataGetBytePtr(value);
    if ((n != 1 && n != 2) || (n == 2 && bytes[1])) return nil;
    return bytes[0] == 'P' ? @"P" : bytes[0] == 'E' ? @"E" : nil;
}
// Validate the actual logical CPU map; neither chip names nor CPU ordering select groups.
typedef struct { int total, performance, efficiency; uint8_t kinds[64]; } CPUTopology;
static BOOL makeTopology(NSArray<NSDictionary *> *cores, int total, int performance, int efficiency,
                         CPUTopology *topology) {
    memset(topology, 0, sizeof(*topology));
    if (total < 2 || total > 64 || performance <= 0 || efficiency <= 0 ||
        performance + efficiency != total || cores.count != (NSUInteger)total) return NO;
    CPUTopology candidate = { .total = total }; BOOL seen[64] = {0};
    for (NSDictionary *core in cores) {
        NSNumber *identifier = core[@"id"]; NSString *kind = core[@"kind"];
        if (![identifier isKindOfClass:NSNumber.class]) return NO;
        int64_t index = identifier.longLongValue;
        if (index < 0 || index >= total || identifier.doubleValue != index || seen[index]) return NO;
        seen[index] = YES;
        if ([kind isEqual:@"P"]) { candidate.kinds[index] = 1; candidate.performance++; }
        else if ([kind isEqual:@"E"]) candidate.efficiency++;
        else return NO;
    }
    if (candidate.performance != performance || candidate.efficiency != efficiency) return NO;
    *topology = candidate; return YES;
}
static uint32_t fourcc(const char *key) {
    return ((uint32_t)(uint8_t)key[0] << 24) | ((uint32_t)(uint8_t)key[1] << 16) |
           ((uint32_t)(uint8_t)key[2] << 8) | (uint8_t)key[3];
}

typedef struct { char key[5]; uint32_t size, type; BOOL checked; } TemperatureSensor;
// Sensor identifiers are hardware facts cross-checked against exelban/stats Sensors/values.swift.
// Select a readable key once; do not scan SMC or guess by prefixes on each timer tick.
static NSArray<NSString *> *temperatureKeys(NSString *chip, BOOL gpu) {
    NSArray *parts = [chip componentsSeparatedByString:@" "];
    NSString *family = parts.count > 1 && [parts[0] isEqual:@"Apple"] ? parts[1] : @"";
    if ([family isEqual:@"M1"])
        return gpu ? @[@"Tg05", @"Tg0D", @"Tg0L", @"Tg0T"] : @[@"Tp05", @"Tp01", @"Tp0D", @"Tp0H"];
    if ([family isEqual:@"M2"])
        return gpu ? @[@"Tg0f", @"Tg0j"] : @[@"Tp05", @"Tp01", @"Tp09", @"Tp0D"];
    if ([family isEqual:@"M3"])
        return gpu ? @[@"Tf14", @"Tf18", @"Tf19", @"Tf1A", @"Tf24", @"Tf28"]
                   : @[@"Tf04", @"Tf09", @"Tf0A", @"Tf0B", @"Tf44"];
    if ([family isEqual:@"M4"])
        return gpu ? @[@"Tg0G", @"Tg0H", @"Tg1U", @"Tg1k", @"Tg0K", @"Tg0L", @"Tg0d", @"Tg0e", @"Tg0j", @"Tg0k"]
                   : @[@"Tp05", @"Tp01", @"Tp09", @"Tp0D"];
    return @[];
}

@implementation TelemetryBackend {
    mach_port_t _host;
    uint64_t _physical;
    BOOL _topologyValid;
    CPUTopology _cpuTopology;
    TemperatureSensor _cpuSensor, _gpuSensor;
    uint32_t _ticks[64][CPU_STATE_MAX];
    natural_t _tickCount;
    double _cpuTime;
    IRAPI _ir;
    IRChannel _gpu, _energy;
    NSArray<NSNumber *> *_gpuFrequencies;
    io_connect_t _smc;
    dispatch_source_t _pressureSource;
    NSUInteger _pressureEvents;
    int _pressureFlag;
    uint64_t _swapIn, _swapOut;
    double _vmTime;
    BOOL _closed;
    NSDictionary<NSString *, NSString *> *_capabilities;
    NetworkSampler *_network;
}

- (NSDictionary<NSString *, NSString *> *)capabilities { return _capabilities; }

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _host = mach_host_self();
    size_t n = sizeof(_physical);
    if (sysctlbyname("hw.memsize", &_physical, &n, NULL, 0) || n != sizeof(_physical)) _physical = 0;
    _topologyValid = [self validateTopology];
    _gpuFrequencies = [self readGPUFrequencies];
    BOOL loaded = [self loadIR];
    if (loaded) {
        [self setupChannel:&_gpu group:CFSTR("GPU Stats") subgroup:CFSTR("GPU Performance States") name:@"GPUPH"];
        [self setupChannel:&_energy group:CFSTR("Energy Model") subgroup:NULL name:@"GPU Energy"];
    }
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service) { IOServiceOpen(service, mach_task_self(), 0, &_smc); IOObjectRelease(service); }
    [self selectTemperature:&_cpuSensor keys:temperatureKeys(sysText("machdep.cpu.brand_string"), NO)];
    [self selectTemperature:&_gpuSensor keys:temperatureKeys(sysText("machdep.cpu.brand_string"), YES)];
    _capabilities = @{ @"topology": _topologyValid ? @"measured" : @"unavailable",
                       @"gpu": _gpu.ready ? @"measured" : @"unavailable",
                       @"gpuPower": _energy.ready ? @"estimated" : @"unavailable",
                       @"smc": _smc ? @"measured" : @"unavailable",
                       @"performanceCores": @(_cpuTopology.performance).stringValue,
                       @"efficiencyCores": @(_cpuTopology.efficiency).stringValue,
                       @"cpuTemperatureSensor": _cpuSensor.key[0] ? [NSString stringWithUTF8String:_cpuSensor.key] : @"unavailable",
                       @"gpuTemperatureSensor": _gpuSensor.key[0] ? [NSString stringWithUTF8String:_gpuSensor.key] : @"unavailable" };
    _pressureSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
        DISPATCH_MEMORYPRESSURE_NORMAL | DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL,
        dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    if (_pressureSource) {
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(_pressureSource, ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            @synchronized (strongSelf) {
                if (strongSelf->_closed || !strongSelf->_pressureSource) return;
                strongSelf->_pressureFlag = (int)dispatch_source_get_data(strongSelf->_pressureSource);
                strongSelf->_pressureEvents++;
            }
            dispatch_block_t changed = strongSelf.pressureChanged;
            if (changed) changed();
        });
        dispatch_resume(_pressureSource);
    }
    if (!getenv("COMPUTE_MONITOR_NETWORK_DISABLED")) _network = [NetworkSampler new];
    (void)[self cpu]; // Prime the first CPU delta without emitting a fake zero.
    return self;
}

- (BOOL)validateTopology {
    memset(&_cpuTopology, 0, sizeof(_cpuTopology));
    int total = sysInt("hw.logicalcpu"), levels = sysInt("hw.nperflevels");
    if (total < 2 || total > 64 || levels < 2 || levels > 8) return NO;
    int performance = 0, efficiency = 0;
    for (int level = 0; level < levels; level++) {
        NSString *prefix = [NSString stringWithFormat:@"hw.perflevel%d", level];
        NSString *name = sysText([[prefix stringByAppendingString:@".name"] UTF8String]);
        int count = sysInt([[prefix stringByAppendingString:@".logicalcpu"] UTF8String]);
        if (count < 1 || count > total) return NO;
        if ([name isEqual:@"Performance"]) performance += count;
        else if ([name isEqual:@"Efficiency"]) efficiency += count;
        else return NO;
    }
    return makeTopology([self readCPUCores], total, performance, efficiency, &_cpuTopology);
}

- (NSArray<NSDictionary *> *)readCPUCores {
    io_registry_entry_t cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus");
    if (!cpus) return @[];
    io_iterator_t iterator = 0;
    kern_return_t kr = IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator);
    IOObjectRelease(cpus);
    if (kr != KERN_SUCCESS) return @[];
    NSMutableArray *cores = [NSMutableArray array];
    io_registry_entry_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        CFTypeRef identifier = IORegistryEntryCreateCFProperty(entry, CFSTR("logical-cpu-id"), kCFAllocatorDefault, 0);
        CFTypeRef kind = IORegistryEntryCreateCFProperty(entry, CFSTR("cluster-type"), kCFAllocatorDefault, 0);
        NSString *type = coreKind(kind); int64_t index = -1;
        if (identifier && CFGetTypeID(identifier) == CFNumberGetTypeID() && !CFNumberIsFloatType(identifier))
            CFNumberGetValue(identifier, kCFNumberSInt64Type, &index);
        [cores addObject:@{ @"id": @(index), @"kind": type ?: @"unknown" }];
        if (identifier) CFRelease(identifier);
        if (kind) CFRelease(kind);
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    return cores;
}

- (NSArray<NSNumber *> *)readGPUFrequencies {
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &iterator) != KERN_SUCCESS) return @[];
    NSMutableArray<NSArray<NSNumber *> *> *tables = [NSMutableArray array];
    io_registry_entry_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        io_name_t name = {0}; IORegistryEntryGetName(entry, name);
        if (!strcmp(name, "pmgr")) {
            CFTypeRef data = IORegistryEntryCreateCFProperty(entry, CFSTR("voltage-states9"), kCFAllocatorDefault, 0);
            NSMutableArray<NSNumber *> *table = [NSMutableArray array];
            if (data && CFGetTypeID(data) == CFDataGetTypeID() && CFDataGetLength(data) % 8 == 0) {
                const uint8_t *bytes = CFDataGetBytePtr(data);
                for (CFIndex offset = 0; offset + 8 <= CFDataGetLength(data); offset += 8) {
                    uint32_t hz = 0; memcpy(&hz, bytes + offset, 4);
                    [table addObject:@(hz / 1e6)];
                }
            }
            [tables addObject:table];
            if (data) CFRelease(data);
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    // Multiple dies must agree; concatenating tables would silently mislabel states.
    NSArray *result = tables.firstObject ?: @[];
    for (NSArray *table in tables) if (![table isEqual:result]) return @[];
    return result;
}

- (BOOL)loadIR {
    _ir.handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (!_ir.handle) return NO;
#define LOAD(field, symbol) _ir.field = (void *)dlsym(_ir.handle, "IOReport" symbol); if (!_ir.field) return NO
    LOAD(copy, "CopyChannelsInGroup"); LOAD(subscribe, "CreateSubscription");
    LOAD(sample, "CreateSamples"); LOAD(delta, "CreateSamplesDelta");
    LOAD(name, "ChannelGetChannelName"); LOAD(unit, "ChannelGetUnitLabel");
    LOAD(integer, "SimpleGetIntegerValue"); LOAD(count, "StateGetCount");
    LOAD(stateName, "StateGetNameForIndex"); LOAD(residency, "StateGetResidency");
#undef LOAD
    return YES;
}

- (void)setupChannel:(IRChannel *)channel group:(CFStringRef)group subgroup:(CFStringRef)subgroup name:(NSString *)wanted {
    CFMutableDictionaryRef all = _ir.copy(group, subgroup, 0, 0, 0);
    if (!all) return;
    CFArrayRef entries = CFDictionaryGetValue(all, CFSTR("IOReportChannels"));
    CFMutableArrayRef picked = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    for (CFIndex i = 0; entries && i < CFArrayGetCount(entries); i++) {
        CFDictionaryRef item = CFArrayGetValueAtIndex(entries, i);
        if ([(__bridge NSString *)_ir.name(item) isEqualToString:wanted]) CFArrayAppendValue(picked, item);
    }
    if (CFArrayGetCount(picked) != 1) { CFRelease(picked); CFRelease(all); return; }
    CFMutableDictionaryRef desired = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, all);
    CFDictionarySetValue(desired, CFSTR("IOReportChannels"), picked);
    CFRelease(picked); CFRelease(all);
    // The subscription does not consume our +1 input dictionary (Step 3.1 ownership check).
    channel->subscription = _ir.subscribe(NULL, desired, &channel->channels, 0, NULL);
    CFRelease(desired);
    if (!channel->subscription || !channel->channels) return;
    CFArrayRef accepted = CFDictionaryGetValue(channel->channels, CFSTR("IOReportChannels"));
    if (!accepted || CFArrayGetCount(accepted) != 1) return;
    channel->previous = _ir.sample(channel->subscription, channel->channels, NULL);
    channel->previousTime = monotonic();
    channel->ready = channel->previous != NULL;
}

- (NSDictionary *)cpu {
    natural_t count = 0; processor_info_array_t data = NULL; mach_msg_type_number_t words = 0;
    kern_return_t kr = host_processor_info(_host, PROCESSOR_CPU_LOAD_INFO, &count, &data, &words);
    double now = monotonic();
    if (kr != KERN_SUCCESS || count == 0 || count > 64 || words < count * CPU_STATE_MAX || !data) {
        if (data) vm_deallocate(mach_task_self(), (vm_address_t)data, words * sizeof(integer_t));
        _tickCount = 0; _cpuTime = 0;
        return @{ @"total": missing(@"invalid", @"host_processor_info", @"read_failed"),
                  @"p": missing(@"unavailable", @"host_processor_info", @"read_failed"),
                  @"e": missing(@"unavailable", @"host_processor_info", @"read_failed") };
    }
    BOOL valid = _tickCount == count && _cpuTime > 0 && now > _cpuTime && now - _cpuTime <= 30;
    double total = 0, p = 0, e = 0;
    for (natural_t i = 0; i < count; i++) {
        uint64_t ticks = 0, busy = 0;
        for (int j = 0; j < CPU_STATE_MAX; j++) {
            uint32_t current = (uint32_t)data[i * CPU_STATE_MAX + j];
            uint32_t difference = current - _ticks[i][j]; _ticks[i][j] = current;
            // Preserve small UInt32 wraps, but reject backward/reset jumps.
            if (difference > INT32_MAX) valid = NO;
            ticks += difference; if (j != CPU_STATE_IDLE) busy += difference;
        }
        if (!ticks) valid = NO;
        double usage = ticks ? (double)busy / ticks : 0;
        total += usage;
        if (_cpuTopology.kinds[i]) p += usage; else e += usage;
    }
    vm_deallocate(mach_task_self(), (vm_address_t)data, words * sizeof(integer_t));
    double window = now - _cpuTime; _tickCount = count; _cpuTime = now;
    BOOL grouped = valid && _topologyValid && count == (natural_t)_cpuTopology.total;
    return @{ @"total": valid ? reading(@(total / count), @"ratio", @"measured", @"host_processor_info", window, nil)
                              : missing(@"unavailable", @"host_processor_info", @"baseline_or_window"),
              @"p": grouped ? reading(@(p / _cpuTopology.performance), @"ratio", @"measured", @"host_processor_info+IODeviceTree", window, nil)
                             : missing(@"unavailable", @"host_processor_info+IODeviceTree", @"topology_or_baseline"),
              @"e": grouped ? reading(@(e / _cpuTopology.efficiency), @"ratio", @"measured", @"host_processor_info+IODeviceTree", window, nil)
                             : missing(@"unavailable", @"host_processor_info+IODeviceTree", @"topology_or_baseline") };
}

- (NSDictionary *)sampleChannel:(IRChannel *)channel gpu:(BOOL)isGPU {
    NSString *source = @"IOReport";
    if (!channel->subscription || !channel->channels) return missing(@"unavailable", source, @"subscription_failed");
    CFDictionaryRef current = _ir.sample(channel->subscription, channel->channels, NULL);
    double now = monotonic();
    if (!current) {
        if (channel->previous) CFRelease(channel->previous);
        channel->previous = NULL;
        return missing(@"invalid", source, @"sample_failed");
    }
    if (!channel->previous) {
        channel->previous = current; channel->previousTime = now;
        return missing(@"unavailable", source, @"baseline_reestablished");
    }
    double window = now - channel->previousTime;
    if (!isfinite(window) || window <= 0 || window > 30) {
        CFRelease(channel->previous); channel->previous = current; channel->previousTime = now;
        return missing(@"stale", source, @"invalid_or_long_window");
    }
    CFDictionaryRef delta = _ir.delta(channel->previous, current, NULL);
    CFRelease(channel->previous); channel->previous = current; channel->previousTime = now;
    if (!delta) {
        CFRelease(channel->previous); channel->previous = NULL;
        return missing(@"invalid", source, @"delta_failed");
    }
    CFArrayRef entries = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
    NSDictionary *result = nil;
    if (!entries || CFArrayGetCount(entries) != 1) result = missing(@"invalid", source, @"channel_count_mismatch");
    else if (isGPU) {
        CFDictionaryRef item = CFArrayGetValueAtIndex(entries, 0);
        int stateCount = _ir.count(item);
        BOOL valid = [(__bridge NSString *)_ir.name(item) isEqualToString:@"GPUPH"] &&
            [(__bridge NSString *)_ir.unit(item) isEqualToString:@"24Mticks"] && stateCount >= 2 && stateCount <= 64;
        BOOL seen[64] = {0}, frequencyValid = YES; double all = 0, active = 0, weighted = 0;
        for (int i = 0; valid && i < stateCount; i++) {
            NSString *state = (__bridge NSString *)_ir.stateName(item, i);
            int index = -1;
            if ([state isEqualToString:@"OFF"]) index = 0;
            else if ([state hasPrefix:@"P"]) {
                NSString *number = [state substringFromIndex:1];
                int parsed = number.intValue;
                if (parsed >= 1 && parsed < stateCount && [number isEqualToString:[NSString stringWithFormat:@"%d", parsed]]) index = parsed;
            }
            int64_t ticks = _ir.residency(item, i);
            if (index < 0 || seen[index] || ticks < 0) { valid = NO; break; }
            seen[index] = YES; all += ticks;
            if (index > 0) {
                active += ticks;
                double mhz = (NSUInteger)index < _gpuFrequencies.count ? _gpuFrequencies[index].doubleValue : 0;
                if (ticks > 0 && (!isfinite(mhz) || mhz <= 0)) frequencyValid = NO;
                else if (ticks > 0) weighted += ticks * mhz;
            }
        }
        for (int i = 0; valid && i < stateCount; i++) if (!seen[i]) valid = NO;
        valid = valid && all > 0 && active <= all && isfinite(active / all);
        if (valid) result = @{ @"active": reading(@(active / all), @"ratio", @"measured", source, window, nil),
                               @"frequency": active > 0 && frequencyValid ? reading(@(weighted / active), @"MHz", @"estimated", @"IOReport+voltage-states9", window, nil)
                                   : missing(@"unavailable", @"IOReport+voltage-states9", active > 0 ? @"frequency_table_unavailable" : @"no_active_residency") };
        else result = missing(@"invalid", source, @"gpu_state_or_unit_mismatch");
    } else {
        CFDictionaryRef item = CFArrayGetValueAtIndex(entries, 0);
        int64_t nJ = _ir.integer(item, NULL);
        double watts = nJ * 1e-9 / window;
        BOOL valid = [(__bridge NSString *)_ir.name(item) isEqualToString:@"GPU Energy"] &&
            [(__bridge NSString *)_ir.unit(item) isEqualToString:@"nJ"] && nJ >= 0 &&
            isfinite(watts) && watts <= 1000;
        result = valid ? reading(@(watts), @"W", @"estimated", source, window, nil)
                       : missing(@"invalid", source, @"gpu_energy_unit_or_delta");
    }
    CFRelease(delta);
    // A broken channel mapping needs a fresh baseline on the next tick.
    if ([result[@"status"] isEqualToString:@"invalid"]) {
        CFRelease(channel->previous); channel->previous = NULL;
    }
    return result;
}

- (NSDictionary<NSString *, NSDictionary *> *)sampleFast {
    NSMutableDictionary *result = [[self cpu] mutableCopy];
    NSDictionary *gpu = [self sampleChannel:&_gpu gpu:YES];
    if (gpu[@"active"]) {
        result[@"gpuActive"] = gpu[@"active"];
        result[@"gpuFrequency"] = gpu[@"frequency"];
    } else {
        result[@"gpuActive"] = gpu;
        result[@"gpuFrequency"] = gpu;
    }
    NetworkRate network = _network ? [_network sample] : (NetworkRate){ .status = NetworkRateUnavailable };
    NSString *status = network.status == NetworkRateMeasured ? @"measured" :
        network.status == NetworkRateInvalid ? @"invalid" :
        network.status == NetworkRateStale ? @"stale" : @"unavailable";
    NSString *reason = _network ? @"no_valid_external_interface_or_baseline" : @"test_disabled";
    result[@"network_rx_bytes_per_sec"] = network.status == NetworkRateMeasured
        ? reading(@(network.receivedBytesPerSecond), @"B/s", status, @"IFMIB_IFDATA", network.windowSeconds, nil)
        : missing(status, @"IFMIB_IFDATA", reason);
    result[@"network_tx_bytes_per_sec"] = network.status == NetworkRateMeasured
        ? reading(@(network.sentBytesPerSecond), @"B/s", status, @"IFMIB_IFDATA", network.windowSeconds, nil)
        : missing(status, @"IFMIB_IFDATA", reason);
    return result;
}

- (NSDictionary *)smc:(const char *)key size:(uint32_t *)size type:(uint32_t *)type checked:(BOOL *)checked {
    NSString *source = [NSString stringWithFormat:@"AppleSMC %.4s", key];
    if (!_smc) return missing(@"unavailable", source, @"smc_open_failed");
    SMCRequest in = {0}, out = {0}; size_t outSize = sizeof(out); in.key = fourcc(key);
    if (!*checked) {
        in.command = 9;
        kern_return_t kr = IOConnectCallStructMethod(_smc, 2, &in, sizeof(in), &out, &outSize);
        if (kr != KERN_SUCCESS || out.result || out.info.size == 0 || out.info.size > 32)
            return missing(@"unavailable", source, @"key_info_failed");
        *size = out.info.size; *type = out.info.type; *checked = YES;
    }
    memset(&in, 0, sizeof(in)); memset(&out, 0, sizeof(out)); outSize = sizeof(out);
    in.key = fourcc(key); in.info.size = *size; in.command = 5;
    kern_return_t kr = IOConnectCallStructMethod(_smc, 2, &in, sizeof(in), &out, &outSize);
    if (kr != KERN_SUCCESS || out.result) return missing(@"invalid", source, @"read_failed");
    float value = 0;
    if (*type == fourcc("flt ") && *size == 4) memcpy(&value, out.bytes, 4);
    else if (*type == fourcc("sp78") && *size == 2) value = (int16_t)((out.bytes[0] << 8) | out.bytes[1]) / 256.0f;
    else return missing(@"unavailable", source, @"unsupported_encoding");
    if (!isfinite(value) || value < 0 || value > 125) return missing(@"invalid", source, @"sensor_range_or_encoding");
    return reading(@(value), @"°C", @"measured", source, 0, nil);
}

- (void)selectTemperature:(TemperatureSensor *)sensor keys:(NSArray<NSString *> *)keys {
    memset(sensor, 0, sizeof(*sensor));
    for (NSString *key in keys) {
        TemperatureSensor candidate = {0}; memcpy(candidate.key, key.UTF8String, 4);
        NSDictionary *value = [self smc:candidate.key size:&candidate.size type:&candidate.type checked:&candidate.checked];
        if ([value[@"status"] isEqual:@"measured"] && [value[@"value"] doubleValue] > 0) {
            *sensor = candidate; return;
        }
    }
}
- (NSDictionary *)temperature:(TemperatureSensor *)sensor {
    if (!sensor->key[0]) return missing(@"unavailable", @"AppleSMC", @"no_supported_temperature_sensor");
    NSDictionary *value = [self smc:sensor->key size:&sensor->size type:&sensor->type checked:&sensor->checked];
    if (value[@"value"] && [value[@"value"] doubleValue] <= 0)
        return missing(@"invalid", value[@"source"], @"inactive_temperature_sensor");
    return value;
}

- (NSDictionary *)vm {
    vm_statistics64_data_t data = {0}; mach_msg_type_number_t n = HOST_VM_INFO64_COUNT;
    kern_return_t kr = host_statistics64(_host, HOST_VM_INFO64, (host_info64_t)&data, &n);
    double now = monotonic();
    if (kr != KERN_SUCCESS || n < HOST_VM_INFO64_COUNT || !_physical || !vm_kernel_page_size) {
        _vmTime = 0;
        NSMutableDictionary *failed = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"free", @"active", @"inactive", @"wired", @"compressed", @"swapIn", @"swapOut"])
            failed[key] = missing(@"invalid", @"HOST_VM_INFO64", @"read_failed");
        failed[@"physical"] = _physical ? reading(@(_physical), @"B", @"measured", @"hw.memsize", 0, nil)
                                       : missing(@"unavailable", @"hw.memsize", @"read_failed");
        return failed;
    }
    uint64_t page = vm_kernel_page_size;
    BOOL rateValid = _vmTime > 0 && now > _vmTime && now - _vmTime <= 30 &&
        data.swapins >= _swapIn && data.swapouts >= _swapOut;
    double window = now - _vmTime;
    double inRate = rateValid ? (data.swapins - _swapIn) / window : 0;
    double outRate = rateValid ? (data.swapouts - _swapOut) / window : 0;
    _vmTime = now; _swapIn = data.swapins; _swapOut = data.swapouts;
    NSMutableDictionary *result = [@{
        @"physical": reading(@(_physical), @"B", @"measured", @"hw.memsize", 0, nil),
        @"free": reading(@(data.free_count * page), @"B", @"measured", @"HOST_VM_INFO64", 0, nil),
        @"active": reading(@(data.active_count * page), @"B", @"measured", @"HOST_VM_INFO64", 0, nil),
        @"inactive": reading(@(data.inactive_count * page), @"B", @"measured", @"HOST_VM_INFO64", 0, nil),
        @"wired": reading(@(data.wire_count * page), @"B", @"measured", @"HOST_VM_INFO64", 0, nil),
        @"compressed": reading(@(data.compressor_page_count * page), @"B", @"measured", @"HOST_VM_INFO64", 0, nil),
        @"swapIn": rateValid ? reading(@(inRate), @"pages/s", @"measured", @"HOST_VM_INFO64", window, nil)
                              : missing(@"unavailable", @"HOST_VM_INFO64", @"baseline_or_window"),
        @"swapOut": rateValid ? reading(@(outRate), @"pages/s", @"measured", @"HOST_VM_INFO64", window, nil)
                               : missing(@"unavailable", @"HOST_VM_INFO64", @"baseline_or_window")
    } mutableCopy];
    return result;
}

- (NSDictionary *)swap {
    struct xsw_usage usage = {0}; size_t n = sizeof(usage);
    if (sysctlbyname("vm.swapusage", &usage, &n, NULL, 0))
        return missing(@"unavailable", @"vm.swapusage", @"sysctl_failed");
    return reading(@(usage.xsu_used), @"B", @"measured", @"vm.swapusage", 0, nil);
}

- (NSDictionary<NSString *, NSDictionary *> *)samplePressure {
    int level = 0; size_t n = sizeof(level);
    NSDictionary *current;
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &n, NULL, 0) == 0) {
        NSString *name = level == 1 ? @"Normal" : level == 2 ? @"Warning" : level == 4 ? @"Critical" : nil;
        current = name ? reading(name, @"", @"measured", @"kern.memorystatus_vm_pressure_level", 0, nil)
                       : missing(@"invalid", @"kern.memorystatus_vm_pressure_level", @"unknown_level");
    } else current = missing(@"unavailable", @"kern.memorystatus_vm_pressure_level", @"sysctl_failed");
    NSUInteger events; int flag;
    @synchronized (self) { events = _pressureEvents; flag = _pressureFlag; }
    NSString *eventName = flag == DISPATCH_MEMORYPRESSURE_NORMAL ? @"Normal" :
        flag == DISPATCH_MEMORYPRESSURE_WARN ? @"Warning" :
        flag == DISPATCH_MEMORYPRESSURE_CRITICAL ? @"Critical" : nil;
    return @{ @"pressure": current,
              @"pressureEvents": _pressureSource ? reading(@(events), @"events", @"measured", @"DispatchSource.memoryPressure", 0, nil)
                                                    : missing(@"unavailable", @"DispatchSource.memoryPressure", @"source_failed"),
              @"pressureLastEvent": eventName ? reading(eventName, @"", @"measured", @"DispatchSource.memoryPressure", 0, nil)
                                                : missing(@"unavailable", @"DispatchSource.memoryPressure", @"no_event") };
}

- (NSDictionary<NSString *, NSDictionary *> *)sampleSlow {
    NSMutableDictionary *result = [[self vm] mutableCopy];
    result[@"swapUsed"] = [self swap];
    result[@"cpuTemperature"] = [self temperature:&_cpuSensor];
    result[@"gpuTemperature"] = [self temperature:&_gpuSensor];
    result[@"gpuPower"] = [self sampleChannel:&_energy gpu:NO];
    [result addEntriesFromDictionary:[self samplePressure]];
    return result;
}

- (void)shutdown {
    @synchronized (self) {
        if (_closed) return;
        _closed = YES;
        if (_pressureSource) { dispatch_source_cancel(_pressureSource); _pressureSource = nil; }
    }
    self.pressureChanged = nil;
    if (_smc) { IOServiceClose(_smc); _smc = 0; }
    IRChannel *channels[] = { &_gpu, &_energy };
    for (int i = 0; i < 2; i++) {
        if (channels[i]->previous) { CFRelease(channels[i]->previous); channels[i]->previous = NULL; }
        if (channels[i]->channels) { CFRelease(channels[i]->channels); channels[i]->channels = NULL; }
        if (channels[i]->subscription) { CFRelease(channels[i]->subscription); channels[i]->subscription = NULL; }
    }
    if (_ir.handle) { dlclose(_ir.handle); _ir.handle = NULL; }
    if (_host) { mach_port_deallocate(mach_task_self(), _host); _host = MACH_PORT_NULL; }
}

#ifdef STEP31_REVIEW
#include "../tests/Step31Diagnostics.inc"
#endif
- (void)dealloc { [self shutdown]; }
@end

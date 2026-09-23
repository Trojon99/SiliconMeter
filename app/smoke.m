#import "TelemetryBackend.h"
#import <sys/resource.h>
#import <libproc.h>
#import <time.h>

static double cpuSeconds(void) {
    struct rusage r = {0}; getrusage(RUSAGE_SELF, &r);
    return r.ru_utime.tv_sec + r.ru_utime.tv_usec / 1e6 + r.ru_stime.tv_sec + r.ru_stime.tv_usec / 1e6;
}
static double monotonic(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}
static void emit(NSDictionary *data) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingSortedKeys error:NULL];
    if (json) { fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout); fflush(stdout); }
}

int main(int argc, const char **argv) { @autoreleasepool {
    int samples = argc > 1 ? atoi(argv[1]) : 8;
    if (samples < 1 || samples > 30) return 2;
    TelemetryBackend *backend = [TelemetryBackend new];
    emit(@{ @"kind": @"capabilities", @"values": backend.capabilities });
    double start = monotonic(), startCPU = cpuSeconds();
    for (int i = 1; i <= samples; i++) {
        struct timespec t = {.tv_sec=2, .tv_nsec=0}; nanosleep(&t, NULL);
        @autoreleasepool {
            NSMutableDictionary *readings = [[backend sampleFast] mutableCopy];
            if (i % 3 == 0) [readings addEntriesFromDictionary:[backend sampleSlow]];
            NSMutableDictionary *brief = [NSMutableDictionary dictionary];
            for (NSString *key in readings) {
                NSDictionary *v = readings[key];
                brief[key] = @{ @"status": v[@"status"] ?: @"invalid", @"value": v[@"value"] ?: [NSNull null] };
            }
            emit(@{ @"kind": @"sample", @"index": @(i), @"values": brief });
        }
    }
    struct rusage_info_v6 r = {0};
    proc_pid_rusage(getpid(), RUSAGE_INFO_V6, (rusage_info_t *)&r);
    pid_t children[32] = {0};
    int childBytes = proc_listchildpids(getpid(), children, sizeof(children));
    emit(@{ @"kind": @"overhead", @"elapsed_s": @(monotonic() - start),
            @"cpu_s": @(cpuSeconds() - startCPU), @"resident_bytes": @(r.ri_resident_size),
            @"child_pid_count": childBytes >= 0 ? @(childBytes / sizeof(pid_t)) : [NSNull null] });
    [backend shutdown];
    return 0;
} }

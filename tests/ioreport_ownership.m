// Protect the input with one extra retain while observing the private ABI.
#import "../app/TelemetryBackend.m"
static IRSubscribe actualSubscribe;
static CFMutableDictionaryRef protectedDesired;
static CFIndex beforeSubscribe, afterSubscribe;
static IRSubscription observeSubscribe(void *a, CFMutableDictionaryRef desired,
    CFMutableDictionaryRef *accepted, uint64_t b, CFTypeRef c) {
    protectedDesired = (CFMutableDictionaryRef)CFRetain(desired);
    beforeSubscribe = CFGetRetainCount(desired);
    IRSubscription sub = actualSubscribe(a, desired, accepted, b, c);
    afterSubscribe = CFGetRetainCount(desired);
    return sub;
}
@implementation TelemetryBackend (OwnershipCheck)
- (void)checkOwnership {
    actualSubscribe = _ir.subscribe;
    if (!actualSubscribe) { fprintf(stderr, "IOReport unavailable\n"); exit(2); }
    _ir.subscribe = observeSubscribe;
    for (NSString *name in @[@"GPUPH", @"GPU Energy"]) {
        BOOL subscribed;
        @autoreleasepool {
        IRChannel test = {0};
        [self setupChannel:&test group:[name isEqual:@"GPUPH"] ? CFSTR("GPU Stats") : CFSTR("Energy Model")
                 subgroup:[name isEqual:@"GPUPH"] ? CFSTR("GPU Performance States") : NULL name:name];
        subscribed = test.subscription && test.channels;
        if (test.previous) CFRelease(test.previous);
        if (test.channels) CFRelease(test.channels);
        if (test.subscription) CFRelease(test.subscription);
        }
        CFIndex afterCleanup = protectedDesired ? CFGetRetainCount(protectedDesired) : -1;
        printf("%s subscribed=%d before=%ld after_call=%ld after_cleanup=%ld\n",
               name.UTF8String, subscribed, beforeSubscribe, afterSubscribe, afterCleanup);
        if (protectedDesired) CFRelease(protectedDesired);
        protectedDesired = NULL;
        if (beforeSubscribe != 2 || afterCleanup != 1) exit(3);
    }
    _ir.subscribe = actualSubscribe;
}
@end
int main(void) { @autoreleasepool {
    TelemetryBackend *backend = [TelemetryBackend new];
    [backend checkOwnership]; [backend shutdown];
    puts("IOREPORT_OWNERSHIP PASS");
} }

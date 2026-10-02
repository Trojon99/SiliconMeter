// Test-only driver for real Sparkle feed/download/installation against a temporary App.
#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>

@interface UpdateHarness : NSObject <SPUUserDriver, SPUUpdaterDelegate>
@property NSString *feed;
@property NSString *mode;
@property BOOL completed;
@property BOOL passed;
@end
@implementation UpdateHarness
- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater { return self.feed; }
// The fixture App is not running. Keep the test controller alive for assertions
// and leave live-App relaunch to a separate acceptance check.
- (BOOL)updaterShouldRelaunchApplication:(SPUUpdater *)updater { return [self.mode isEqual:@"live-install"]; }
- (void)finish:(BOOL)passed message:(NSString *)message {
    printf("UPDATE_HARNESS %s\n", message.UTF8String); fflush(stdout);
    self.passed = passed; self.completed = YES;
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {
    reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]);
}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply {
    printf("UPDATE_FOUND version=%s\n", item.versionString.UTF8String); fflush(stdout);
    reply([self.mode isEqual:@"install"] || [self.mode isEqual:@"live-install"] || [self.mode isEqual:@"bad-archive"] ? SPUUserUpdateChoiceInstall : SPUUserUpdateChoiceDismiss);
    if ([self.mode isEqual:@"found"]) [self finish:[item.versionString isEqual:@"3"] message:@"NEW_VERSION_AVAILABLE"];
}
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))ack {
    ack(); [self finish:[self.mode isEqual:@"current"] message:[NSString stringWithFormat:@"NO_UPDATE code=%ld", (long)error.code]];
}
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))ack {
    ack();
    fprintf(stderr, "SPARKLE_ERROR %s\n", error.description.UTF8String);
    BOOL signatureFailure = NO;
    for (NSError *cause = error; cause; cause = cause.userInfo[NSUnderlyingErrorKey]) {
        if ([cause.domain isEqual:SUSparkleErrorDomain] &&
            (cause.code == SUSignatureError || cause.code == SUValidationError)) signatureFailure = YES;
    }
    BOOL expected = [error.domain isEqual:SUSparkleErrorDomain] && (([self.mode isEqual:@"bad-feed"] && error.code == SUAppcastParseError) ||
                    ([self.mode isEqual:@"bad-archive"] && signatureFailure) ||
                    ([self.mode isEqual:@"offline"] && error.code == SUDownloadError));
    [self finish:expected message:[NSString stringWithFormat:@"ERROR code=%ld description=%@", (long)error.code, error.localizedDescription]];
}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate { puts("UPDATE_EXTRACTING"); fflush(stdout); }
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply {
    puts("UPDATE_READY"); fflush(stdout); reply(SPUUserUpdateChoiceInstall);
}
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))ack {
    ack(); [self finish:[self.mode isEqual:@"install"] message:[NSString stringWithFormat:@"INSTALLED relaunched=%d", relaunched]];
}
- (void)dismissUpdateInstallation {}
@end

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 4) return 2;
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSBundle *host = [NSBundle bundleWithPath:@(argv[1])];
    // The calling script owns the isolated host path and verifies its contents afterward.
    if (!host || ![host.bundlePath containsString:@"siliconmeter-update-test-"]) return 2;
    UpdateHarness *driver = [UpdateHarness new]; driver.feed = @(argv[2]); driver.mode = @(argv[3]);
    SPUUpdater *updater = [[SPUUpdater alloc] initWithHostBundle:host applicationBundle:host userDriver:driver delegate:driver];
    NSError *error = nil;
    if (![updater startUpdater:&error]) { fprintf(stderr, "START_FAILED %s\n", error.description.UTF8String); return 3; }
    if ([driver.mode isEqual:@"live-install"]) {
        // Real AppKit event dispatch is needed to receive Sparkle's quit event.
        dispatch_async(dispatch_get_main_queue(), ^{ [updater checkForUpdates]; });
        [NSApp run];
        return 4;
    }
    [updater checkForUpdates];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:55];
    while (!driver.completed && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    if (!driver.completed) { fputs("UPDATE_HARNESS TIMEOUT\n", stderr); return 4; }
    return driver.passed ? 0 : 1;
} }

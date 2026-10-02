// Harmless donor fixture: proves Sparkle relaunched the replacement App without
// starting telemetry or touching the installed SiliconMeter data directory.
#import <AppKit/AppKit.h>
#include <unistd.h>

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *marker = info[@"UpdateTestLaunchMarker"];
    if (![marker containsString:@"siliconmeter-update-test-"]) return 2;
    NSDictionary *result = @{@"build": info[@"CFBundleVersion"],
                             @"identifier": info[@"CFBundleIdentifier"],
                             @"pid": @(getpid())};
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    return [data writeToFile:marker atomically:YES] ? 0 : 3;
} }

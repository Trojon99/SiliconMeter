#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The backend is confined to the telemetry service's serial queue.
@interface TelemetryBackend : NSObject
@property (nonatomic, copy, nullable) dispatch_block_t pressureChanged;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *capabilities;
- (NSDictionary<NSString *, NSDictionary *> *)sampleFast;
- (NSDictionary<NSString *, NSDictionary *> *)sampleSlow;
- (NSDictionary<NSString *, NSDictionary *> *)samplePressure;
- (void)shutdown;
@end

NS_ASSUME_NONNULL_END

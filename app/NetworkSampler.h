#import <Foundation/Foundation.h>
#import <net/if.h>
#include <stdint.h>

typedef struct {
    char name[IF_NAMESIZE];
    unsigned int index;
    uint64_t receivedBytes;
    uint64_t sentBytes;
    int64_t linkChangeSeconds;
    int64_t linkChangeMicroseconds;
} NetworkCounter;

typedef enum {
    NetworkRateMeasured,
    NetworkRateUnavailable,
    NetworkRateInvalid,
    NetworkRateStale
} NetworkRateStatus;

typedef struct {
    NetworkRateStatus status;
    double receivedBytesPerSecond;
    double sentBytesPerSecond;
    double windowSeconds;
    double sampleMilliseconds;
    unsigned int interfaceCount;
} NetworkRate;

enum { NetworkMaximumInterfaces = 64 };
typedef struct { NetworkCounter counter; double timestamp; } NetworkBaseline;
typedef struct { NetworkBaseline entries[NetworkMaximumInterfaces]; size_t count; } NetworkAccumulator;

BOOL NetworkInterfaceEligible(const char *name, unsigned char type, int flags, uint64_t baudrate);
NetworkRate NetworkAccumulatorUpdate(NetworkAccumulator *state, const NetworkCounter *counters,
                                     size_t count, double now);

@interface NetworkSampler : NSObject
- (NetworkRate)sample;
@end

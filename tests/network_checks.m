#import "../app/NetworkSampler.h"
#import <net/if_types.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int checks;
#define CHECK(value) do { ++checks; if (!(value)) { fprintf(stderr, "NETWORK_CHECK FAIL line %d\n", __LINE__); exit(1); } } while (0)
static NetworkCounter counter(const char *name, unsigned index, uint64_t rx, uint64_t tx, int64_t change) {
    NetworkCounter c = {0};
    strlcpy(c.name, name, sizeof(c.name));
    c.index = index; c.receivedBytes = rx; c.sentBytes = tx; c.linkChangeSeconds = change;
    return c;
}

int main(void) {
    @autoreleasepool {
        CHECK(NetworkInterfaceEligible("en0", IFT_ETHER, IFF_UP|IFF_RUNNING, 100000000));
        CHECK(NetworkInterfaceEligible("en7", IFT_ETHER, IFF_UP|IFF_RUNNING, 100000000));
        CHECK(!NetworkInterfaceEligible("en0", IFT_ETHER, IFF_UP|IFF_RUNNING, 0));
        CHECK(!NetworkInterfaceEligible("en0", IFT_ETHER, IFF_UP, 100000000));
        CHECK(!NetworkInterfaceEligible("awdl0", IFT_ETHER, IFF_UP|IFF_RUNNING, 100000000));
        CHECK(!NetworkInterfaceEligible("bridge0", IFT_ETHER, IFF_UP|IFF_RUNNING, 100000000));
        CHECK(!NetworkInterfaceEligible("utun0", IFT_ETHER, IFF_UP|IFF_RUNNING, 100000000));
        CHECK(!NetworkInterfaceEligible("ap1", IFT_ETHER, IFF_UP|IFF_RUNNING, 100000000));
        CHECK(!NetworkInterfaceEligible("en0", IFT_LOOP, IFF_UP|IFF_RUNNING, 100000000));
        NetworkAccumulator state = {0};
        NetworkCounter pair[] = {counter("en0", 14, 1000, 2000, 1), counter("en7", 23, 500, 900, 1)};
        CHECK(NetworkAccumulatorUpdate(&state, pair, 2, 10).status == NetworkRateUnavailable);
        pair[0].receivedBytes += 200; pair[0].sentBytes += 100;
        pair[1].receivedBytes += 100; pair[1].sentBytes += 300;
        NetworkRate measured = NetworkAccumulatorUpdate(&state, pair, 2, 12);
        CHECK(measured.status == NetworkRateMeasured && measured.receivedBytesPerSecond == 150 &&
              measured.sentBytesPerSecond == 200 && measured.windowSeconds == 2);
        measured = NetworkAccumulatorUpdate(&state, pair, 2, 14);
        CHECK(measured.status == NetworkRateMeasured && measured.receivedBytesPerSecond == 0 &&
              measured.sentBytesPerSecond == 0);
        CHECK(NetworkAccumulatorUpdate(&state, pair, 1, 16).status == NetworkRateMeasured);
        CHECK(NetworkAccumulatorUpdate(&state, pair, 2, 18).status == NetworkRateUnavailable); // Reappearing en7
        pair[1].receivedBytes += 40;
        CHECK(NetworkAccumulatorUpdate(&state, pair, 2, 20).status == NetworkRateMeasured);
        pair[0].receivedBytes = 5;
        CHECK(NetworkAccumulatorUpdate(&state, pair, 2, 22).status == NetworkRateUnavailable); // Counter reset
        pair[0].receivedBytes += 5;
        CHECK(NetworkAccumulatorUpdate(&state, pair, 2, 24).status == NetworkRateMeasured);
        pair[0].index = 50;
        CHECK(NetworkAccumulatorUpdate(&state, pair, 2, 26).status == NetworkRateUnavailable); // New ifindex
        pair[0].linkChangeSeconds = 2;
        CHECK(NetworkAccumulatorUpdate(&state, pair, 2, 28).status == NetworkRateUnavailable); // Link transition
        CHECK(NetworkAccumulatorUpdate(&state, pair, 2, 70).status == NetworkRateStale);
        CHECK(NetworkAccumulatorUpdate(&state, NULL, 0, 72).status == NetworkRateUnavailable);
        CHECK(NetworkAccumulatorUpdate(&state, pair, 2, 74).status == NetworkRateUnavailable);
        NetworkSampler *sampler = [NetworkSampler new];
        NetworkRate first = [sampler sample];
        [NSThread sleepForTimeInterval:2.1];
        NetworkRate second = [sampler sample];
        CHECK(first.status == NetworkRateUnavailable || first.status == NetworkRateInvalid);
        CHECK(second.status == NetworkRateMeasured || second.status == NetworkRateUnavailable);
        printf("NETWORK_CHECK PASS assertions=%d first=%d second=%d interfaces=%u rx=%.1f tx=%.1f sample_ms=%.3f\n",
               checks, first.status, second.status, second.interfaceCount,
               second.receivedBytesPerSecond, second.sentBytesPerSecond, second.sampleMilliseconds);
    }
}

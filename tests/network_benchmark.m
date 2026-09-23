#import "../app/NetworkSampler.h"
#include <stdio.h>
#include <stdlib.h>

static int compare(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

int main(void) {
    @autoreleasepool {
        NetworkSampler *sampler = [NetworkSampler new];
        double times[100], sum = 0;
        unsigned measured = 0, invalid = 0;
        for (unsigned i = 0; i < 100; ++i) {
            NetworkRate rate = [sampler sample];
            times[i] = rate.sampleMilliseconds;
            sum += times[i];
            measured += rate.status == NetworkRateMeasured;
            invalid += rate.status == NetworkRateInvalid;
            [NSThread sleepForTimeInterval:0.01];
        }
        qsort(times, 100, sizeof(double), compare);
        printf("{\"samples\":100,\"mean_ms\":%.3f,\"median_ms\":%.3f,\"p95_ms\":%.3f,\"max_ms\":%.3f,\"measured\":%u,\"invalid\":%u}\n",
               sum/100, (times[49]+times[50])/2, times[94], times[99], measured, invalid);
    }
}

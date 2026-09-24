#import "NetworkSampler.h"
#import <net/if_mib.h>
#import <net/if_types.h>
#import <net/route.h>
#import <sys/socket.h>
#import <sys/sysctl.h>
#import <time.h>
#import <errno.h>
#import <math.h>
#import <string.h>

static double networkMonotonic(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t) != 0) return NAN;
    return t.tv_sec + t.tv_nsec / 1e9;
}

static BOOL begins(const char *name, const char *prefix) {
    return strncmp(name, prefix, strlen(prefix)) == 0;
}

BOOL NetworkInterfaceEligible(const char *name, unsigned char type, int flags, uint64_t baudrate) {
    if (!name || !name[0] || type != IFT_ETHER || baudrate == 0 ||
        (flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING)) return NO;
    const char *excluded[] = {"lo", "utun", "awdl", "llw", "gif", "stf", "bridge", "vmnet",
                              "vmenet", "vboxnet", "tap", "tun", "p2p", "ap", "anpi",
                              "nan", "ipsec", "faith"};
    for (size_t i = 0; i < sizeof(excluded) / sizeof(excluded[0]); ++i)
        if (begins(name, excluded[i])) return NO;
    return YES;
}

NetworkRate NetworkAccumulatorUpdate(NetworkAccumulator *state, const NetworkCounter *counters,
                                     size_t count, double now) {
    NetworkRate result = { .status = NetworkRateUnavailable, .interfaceCount = (unsigned int)count };
    if (!state || (!counters && count) || count > NetworkMaximumInterfaces || !isfinite(now)) {
        result.status = NetworkRateInvalid;
        return result;
    }
    NetworkAccumulator next = {0};
    next.count = count;
    BOOL needsBaseline = count == 0, stale = NO;
    double window = 0;
    for (size_t i = 0; i < count; ++i) {
        const NetworkCounter *current = &counters[i];
        if (!current->name[0] || !memchr(current->name, 0, IF_NAMESIZE)) {
            result.status = NetworkRateInvalid;
            return result;
        }
        for (size_t j = 0; j < i; ++j) {
            if (!strcmp(current->name, counters[j].name) || current->index == counters[j].index) {
                result.status = NetworkRateInvalid;
                return result;
            }
        }
        next.entries[i] = (NetworkBaseline){ .counter = *current, .timestamp = now };
        const NetworkBaseline *old = NULL;
        for (size_t j = 0; j < state->count; ++j)
            if (!strcmp(state->entries[j].counter.name, current->name)) {
                old = &state->entries[j];
                break;
            }
        if (!old || old->counter.index != current->index ||
            old->counter.linkChangeSeconds != current->linkChangeSeconds ||
            old->counter.linkChangeMicroseconds != current->linkChangeMicroseconds ||
            current->receivedBytes < old->counter.receivedBytes ||
            current->sentBytes < old->counter.sentBytes) {
            needsBaseline = YES;
            continue;
        }
        double delta = now - old->timestamp;
        if (!isfinite(delta) || delta <= 0 || delta > 30) {
            stale = YES;
            continue;
        }
        window = delta;
        result.receivedBytesPerSecond += (double)(current->receivedBytes - old->counter.receivedBytes) / delta;
        result.sentBytesPerSecond += (double)(current->sentBytes - old->counter.sentBytes) / delta;
    }
    *state = next; // Missing/down interfaces disappear; reappearance gets a fresh baseline.
    if (stale) result.status = NetworkRateStale;
    else if (needsBaseline) result.status = NetworkRateUnavailable;
    else if (!isfinite(result.receivedBytesPerSecond) || !isfinite(result.sentBytesPerSecond))
        result.status = NetworkRateInvalid;
    else { result.status = NetworkRateMeasured; result.windowSeconds = window; }
    if (result.status != NetworkRateMeasured)
        result.receivedBytesPerSecond = result.sentBytesPerSecond = 0;
    return result;
}

@implementation NetworkSampler {
    NetworkAccumulator _baselines;
}

- (NetworkRate)sample {
    double start = networkMonotonic();
    NetworkRate failure = { .status = NetworkRateInvalid };
    int mib[6] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0 };
    size_t length = 0;
    if (sysctl(mib, 6, NULL, &length, NULL, 0) != 0 || length == 0 || length > 1024 * 1024)
        return failure;
    void *buffer = NULL;
    for (int attempt = 0; attempt < 2; ++attempt) {
        void *candidate = malloc(length);
        if (!candidate) return failure;
        size_t actual = length;
        if (sysctl(mib, 6, candidate, &actual, NULL, 0) == 0) {
            buffer = candidate;
            length = actual;
            break;
        }
        int error = errno;
        free(candidate);
        if (error != ENOMEM || sysctl(mib, 6, NULL, &length, NULL, 0) != 0 || length > 1024 * 1024)
            return failure;
    }
    if (!buffer) return failure;
    NetworkCounter counters[NetworkMaximumInterfaces] = {0};
    size_t count = 0, offset = 0;
    BOOL valid = YES;
    while (offset < length) {
        struct { unsigned short msglen; unsigned char version; unsigned char type; } header;
        if (length - offset < sizeof(header)) { valid = NO; break; }
        memcpy(&header, (char *)buffer + offset, sizeof(header));
        if (header.msglen < sizeof(header) || header.msglen > length - offset) { valid = NO; break; }
        if (header.type == RTM_IFINFO2) {
            if (header.msglen < sizeof(struct if_msghdr2)) { valid = NO; break; }
            struct if_msghdr2 item;
            memcpy(&item, (char *)buffer + offset, sizeof(item));
            if (item.ifm_data.ifi_type == IFT_ETHER && item.ifm_data.ifi_baudrate > 0 &&
                (item.ifm_flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)) {
                char name[IF_NAMESIZE] = {0};
                if (!if_indextoname(item.ifm_index, name)) { valid = NO; break; }
                if (NetworkInterfaceEligible(name, item.ifm_data.ifi_type,
                                             item.ifm_flags, item.ifm_data.ifi_baudrate)) {
                    if (count == NetworkMaximumInterfaces) { valid = NO; break; }
                    // RTM_IFINFO2 truncates byte counts at 32 bits on this macOS build.
                    // Read the same interface's full if_data64 counters via ifmib.
                    int dataMib[6] = { CTL_NET, PF_LINK, NETLINK_GENERIC,
                                       IFMIB_IFDATA, item.ifm_index, IFDATA_GENERAL };
                    struct ifmibdata data = {0};
                    size_t dataLength = sizeof(data);
                    if (sysctl(dataMib, 6, &data, &dataLength, NULL, 0) != 0 ||
                        dataLength != sizeof(data) ||
                        strncmp(data.ifmd_name, name, sizeof(data.ifmd_name)) != 0 ||
                        !NetworkInterfaceEligible(name, data.ifmd_data.ifi_type,
                                                  data.ifmd_flags, data.ifmd_data.ifi_baudrate)) {
                        valid = NO;
                        break;
                    }
                    NetworkCounter *counter = &counters[count++];
                    memcpy(counter->name, name, IF_NAMESIZE);
                    counter->index = item.ifm_index;
                    counter->receivedBytes = data.ifmd_data.ifi_ibytes;
                    counter->sentBytes = data.ifmd_data.ifi_obytes;
                    counter->linkChangeSeconds = data.ifmd_data.ifi_lastchange.tv_sec;
                    counter->linkChangeMicroseconds = data.ifmd_data.ifi_lastchange.tv_usec;
                }
            }
        }
        offset += header.msglen;
    }
    free(buffer);
    if (!valid) return failure;
    NetworkRate result = NetworkAccumulatorUpdate(&_baselines, counters, count, networkMonotonic());
    result.sampleMilliseconds = (networkMonotonic() - start) * 1000;
    return result;
}
@end

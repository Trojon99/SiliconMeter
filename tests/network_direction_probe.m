// Test-only direct view of the same Darwin interface counters and eligibility
// predicate used by NetworkSampler. Never linked into the ordinary app.
#import "../app/NetworkSampler.h"
#import <Foundation/Foundation.h>
#import <net/if_mib.h>
#import <net/route.h>
#import <sys/sysctl.h>
#import <time.h>
#import <math.h>

static double monotonicSeconds(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t) != 0) return NAN;
    return t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL inventory = argc == 2 && strcmp(argv[1], "--inventory") == 0;
        if (argc != 2 || (!inventory && strcmp(argv[1], "--sample") != 0)) return 2;
        int mib[6] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
        size_t length = 0;
        if (sysctl(mib, 6, NULL, &length, NULL, 0) != 0 || length == 0 || length > 1024 * 1024)
            return 3;
        void *buffer = malloc(length);
        if (!buffer) return 4;
        size_t actual = length;
        if (sysctl(mib, 6, buffer, &actual, NULL, 0) != 0) { free(buffer); return 5; }
        NSMutableArray *interfaces = [NSMutableArray array];
        size_t offset = 0;
        while (offset < actual) {
            struct { unsigned short msglen; unsigned char version; unsigned char type; } header;
            if (actual - offset < sizeof(header)) { free(buffer); return 6; }
            memcpy(&header, (char *)buffer + offset, sizeof(header));
            if (header.msglen < sizeof(header) || header.msglen > actual - offset) {
                free(buffer); return 7;
            }
            if (header.type == RTM_IFINFO2) {
                if (header.msglen < sizeof(struct if_msghdr2)) { free(buffer); return 8; }
                struct if_msghdr2 item;
                memcpy(&item, (char *)buffer + offset, sizeof(item));
                char name[IF_NAMESIZE] = {0};
                if (!if_indextoname(item.ifm_index, name)) { free(buffer); return 9; }
                BOOL selected = NetworkInterfaceEligible(name, item.ifm_data.ifi_type,
                    item.ifm_flags, item.ifm_data.ifi_baudrate);
                if (inventory || selected) {
                    uint64_t rx = item.ifm_data.ifi_ibytes, tx = item.ifm_data.ifi_obytes;
                    if (selected) {
                        int dataMib[6] = {CTL_NET, PF_LINK, NETLINK_GENERIC,
                                          IFMIB_IFDATA, item.ifm_index, IFDATA_GENERAL};
                        struct ifmibdata data = {0};
                        size_t dataLength = sizeof(data);
                        if (sysctl(dataMib, 6, &data, &dataLength, NULL, 0) != 0 ||
                            dataLength != sizeof(data) ||
                            strncmp(data.ifmd_name, name, sizeof(data.ifmd_name)) != 0) {
                            free(buffer); return 11;
                        }
                        rx = data.ifmd_data.ifi_ibytes;
                        tx = data.ifmd_data.ifi_obytes;
                    }
                    [interfaces addObject:@{
                        @"name": [NSString stringWithUTF8String:name],
                        @"index": @(item.ifm_index), @"selected": @(selected),
                        @"type": @(item.ifm_data.ifi_type), @"flags": @(item.ifm_flags),
                        @"baudrate": @(item.ifm_data.ifi_baudrate),
                        @"rx_bytes": @(rx), @"tx_bytes": @(tx),
                        @"route_rx_bytes": @(item.ifm_data.ifi_ibytes),
                        @"route_tx_bytes": @(item.ifm_data.ifi_obytes),
                        @"link_change_s": @(item.ifm_data.ifi_lastchange.tv_sec),
                        @"link_change_us": @(item.ifm_data.ifi_lastchange.tv_usec)
                    }];
                }
            }
            offset += header.msglen;
        }
        free(buffer);
        NSDictionary *result = @{@"utc_ms": @((long long)([NSDate date].timeIntervalSince1970 * 1000)),
            @"monotonic_s": @(monotonicSeconds()), @"interfaces": interfaces};
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:NULL];
        if (!json) return 10;
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return 0;
    }
}

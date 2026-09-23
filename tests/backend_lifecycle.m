#import "../app/TelemetryBackend.m"
#import <libproc.h>

static unsigned portNames(void) {
    mach_port_name_array_t names = NULL; mach_port_type_array_t types = NULL;
    mach_msg_type_number_t n = 0, t = 0;
    if (mach_port_names(mach_task_self(), &names, &n, &types, &t) != KERN_SUCCESS) exit(2);
    vm_deallocate(mach_task_self(), (vm_address_t)names, n * sizeof(*names));
    vm_deallocate(mach_task_self(), (vm_address_t)types, t * sizeof(*types));
    return n;
}
static void lifecycle(void) { @autoreleasepool {
    TelemetryBackend *backend = [TelemetryBackend new];
    (void)[backend sampleFast]; (void)[backend sampleSlow];
    [backend shutdown]; [backend shutdown];
} }
int main(void) { @autoreleasepool {
    for (int i = 0; i < 10; i++) { lifecycle(); usleep(10000); }
    usleep(100000);
    mach_port_t host = mach_host_self();
    mach_port_urefs_t before = 0, after = 0;
    mach_port_get_refs(mach_task_self(), host, MACH_PORT_RIGHT_SEND, &before);
    unsigned first = portNames();
    for (int i = 0; i < 100; i++) { lifecycle(); usleep(10000); }
    usleep(100000);
    unsigned last = portNames();
    mach_port_get_refs(mach_task_self(), host, MACH_PORT_RIGHT_SEND, &after);
    mach_port_deallocate(mach_task_self(), host);
    printf("BACKEND_LIFECYCLE iterations=100 host_refs=%u->%u port_names=%u->%u\n", before, after, first, last);
    return before == after && last <= first + 2 ? 0 : 3;
} }

// Test-only self observation; never compiled into the normal app.
- (NSDictionary *)reviewResources {
    struct rusage r = {0}; getrusage(RUSAGE_SELF, &r);
    struct rusage_info_v6 info = {0};
    int rc = proc_pid_rusage(getpid(), RUSAGE_INFO_V6, (rusage_info_t *)&info);
    mach_port_urefs_t refs = 0;
    kern_return_t kr = mach_port_get_refs(mach_task_self(), _host, MACH_PORT_RIGHT_SEND, &refs);
    pid_t children[128]; int bytes = proc_listchildpids(getpid(), children, sizeof(children));
    struct proc_taskinfo task = {0};
    int taskBytes = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &task, sizeof(task));
    mach_port_name_array_t names = NULL; mach_port_type_array_t types = NULL;
    mach_msg_type_number_t nameCount = 0, typeCount = 0;
    kern_return_t namesKR = mach_port_names(mach_task_self(), &names, &nameCount, &types, &typeCount);
    if (names) vm_deallocate(mach_task_self(), (vm_address_t)names, nameCount * sizeof(*names));
    if (types) vm_deallocate(mach_task_self(), (vm_address_t)types, typeCount * sizeof(*types));
    return @{ @"pid": @(getpid()),
        @"cpu_s": @(r.ru_utime.tv_sec + r.ru_utime.tv_usec / 1e6 + r.ru_stime.tv_sec + r.ru_stime.tv_usec / 1e6),
        @"rss_bytes": rc == 0 ? @(info.ri_resident_size) : [NSNull null],
        @"peak_rss_bytes": @(r.ru_maxrss),
        @"host_refs": kr == KERN_SUCCESS ? @(refs) : [NSNull null],
        @"port_names": namesKR == KERN_SUCCESS ? @(nameCount) : [NSNull null],
        @"threads": taskBytes == sizeof(task) ? @(task.pti_threadnum) : [NSNull null],
        @"children": bytes >= 0 && (size_t)bytes < sizeof(children) ? @(bytes / sizeof(pid_t)) : [NSNull null],
        @"interrupt_wakeups": rc == 0 ? @(info.ri_interrupt_wkups) : [NSNull null],
        @"package_idle_wakeups": rc == 0 ? @(info.ri_pkg_idle_wkups) : [NSNull null],
        @"capabilities": self.capabilities };
}

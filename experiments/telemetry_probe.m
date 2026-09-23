// Disposable macOS 27 telemetry experiment. No application code depends on it.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <IOKit/IOKitLib.h>
#import <mach/mach.h>
#import <mach/processor_info.h>
#import <sys/sysctl.h>
#import <sys/resource.h>
#import <libproc.h>
#import <dlfcn.h>
#import <time.h>
#import <stdatomic.h>

typedef void *IRSubscription;
typedef CFMutableDictionaryRef (*IRCopyGroup)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
typedef IRSubscription (*IRSubscribe)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*IRSample)(IRSubscription, CFMutableDictionaryRef, CFTypeRef);
typedef CFDictionaryRef (*IRDelta)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
typedef CFStringRef (*IRString)(CFDictionaryRef);
typedef int64_t (*IRInteger)(CFDictionaryRef, void *);
typedef int32_t (*IRStateCount)(CFDictionaryRef);
typedef CFStringRef (*IRStateName)(CFDictionaryRef, int32_t);
typedef int64_t (*IRResidency)(CFDictionaryRef, int32_t);

static struct {
  void *handle; IRCopyGroup copy; IRSubscribe subscribe; IRSample sample; IRDelta delta;
  IRString name, subgroup, unit; IRInteger integer;
  IRStateCount states; IRStateName stateName; IRResidency residency;
} ir;

typedef struct {
  const char *label; CFStringRef group, subgroup;
  CFMutableDictionaryRef subscribed; IRSubscription subscription;
  CFDictionaryRef previous; double previousTime; BOOL resetPending;
  long enumerated, selected, subscribedCount;
  char error[64];
} IRGroup;
static IRGroup irGroups[] = {
  {.label="gpu", .group=CFSTR("GPU Stats"), .subgroup=CFSTR("GPU Performance States")},
  {.label="power", .group=CFSTR("Energy Model")},
  {.label="cpustates", .group=CFSTR("CPU Stats"), .subgroup=CFSTR("CPU Complex Performance States")},
  {.label="bandwidth", .group=CFSTR("AMC Stats"), .subgroup=CFSTR("Perf Counters")},
  {.label="pmp", .group=CFSTR("PMP"), .subgroup=CFSTR("DCS BW")}
};

static double nowSeconds(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec+t.tv_nsec/1e9; }
static NSString *s(CFStringRef x) { return x ? (__bridge NSString *)x : @""; }
static BOOL unfiltered=NO;
static NSArray<NSNumber *> *gpuFreqs;
static mach_port_t hostPort=MACH_PORT_NULL;
static uint64_t physicalBytes=0;
static BOOL peTopologyValid=NO;
static NSString *topologyReason=@"not_checked";
static const int8_t expectedCoreType[10]={0,0,1,1,1,1,1,1,1,1};

static BOOL sysctlString(const char *key, const char *expected) {
  char value[128]={0}; size_t size=sizeof(value);
  return sysctlbyname(key,value,&size,NULL,0)==0 && size>0 && !strcmp(value,expected);
}
static BOOL sysctlCount(const char *key, int expected) {
  int value=0; size_t size=sizeof(value);
  return sysctlbyname(key,&value,&size,NULL,0)==0 && size==sizeof(value) && value==expected;
}
static BOOL dataEquals(CFTypeRef value, const char *word) {
  if (!value || CFGetTypeID(value)!=CFDataGetTypeID()) return NO;
  CFDataRef data=(CFDataRef)value; size_t n=strlen(word);
  return CFDataGetLength(data)>=(CFIndex)n && !memcmp(CFDataGetBytePtr(data),word,n);
}
static NSDictionary *checkTopology(void) {
  if (!sysctlString("machdep.cpu.brand_string","Apple M1 Max") ||
      !sysctlCount("hw.ncpu",10) || !sysctlCount("hw.perflevel0.logicalcpu",8) ||
      !sysctlCount("hw.perflevel1.logicalcpu",2) ||
      !sysctlString("hw.perflevel0.name","Performance") ||
      !sysctlString("hw.perflevel1.name","Efficiency")) {
    topologyReason=@"chip_or_perflevel_mismatch";
    return @{ @"status":@"unavailable", @"reason":topologyReason };
  }
  io_registry_entry_t cpus=IORegistryEntryFromPath(kIOMainPortDefault,"IODeviceTree:/cpus");
  if (!cpus) { topologyReason=@"device_tree_missing"; return @{ @"status":@"unavailable", @"reason":topologyReason }; }
  io_iterator_t it=0; kern_return_t kr=IORegistryEntryGetChildIterator(cpus,kIODeviceTreePlane,&it);
  IOObjectRelease(cpus);
  if (kr!=KERN_SUCCESS) { topologyReason=@"cpu_iterator_failed"; return @{ @"status":@"unavailable", @"reason":topologyReason }; }
  BOOL seen[10]={0}; int found=0; BOOL valid=YES; io_registry_entry_t entry;
  while ((entry=IOIteratorNext(it))) {
    CFTypeRef id=IORegistryEntryCreateCFProperty(entry,CFSTR("logical-cpu-id"),kCFAllocatorDefault,0);
    CFTypeRef kind=IORegistryEntryCreateCFProperty(entry,CFSTR("cluster-type"),kCFAllocatorDefault,0);
    int64_t index=-1;
    if (id && CFGetTypeID(id)==CFNumberGetTypeID() && CFNumberGetValue((CFNumberRef)id,kCFNumberSInt64Type,&index)) {
      if (index<0 || index>=10 || seen[index]) valid=NO;
      else {
        seen[index]=YES; found++;
        if (!dataEquals(kind,expectedCoreType[index] ? "P":"E")) valid=NO;
      }
    }
    if (id) CFRelease(id); if (kind) CFRelease(kind); IOObjectRelease(entry);
  }
  IOObjectRelease(it);
  peTopologyValid=valid && found==10;
  topologyReason=peTopologyValid?@"validated_m1_max_0_1_e_2_9_p":@"device_tree_mapping_mismatch";
  return @{ @"status":peTopologyValid?@"measured":@"unavailable", @"reason":topologyReason,
            @"logical_cpus":@(found), @"source":@"IODeviceTree+sysctl" };
}

static NSArray<NSNumber *> *readGPUFreqs(void) {
  io_iterator_t iter=0;
  if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("AppleARMIODevice"),&iter)!=KERN_SUCCESS) return @[];
  NSMutableArray<NSNumber *> *result=[NSMutableArray array];
  io_registry_entry_t entry=0;
  while((entry=IOIteratorNext(iter))) {
    io_name_t name={0}; IORegistryEntryGetName(entry,name);
    if(!strcmp(name,"pmgr")) {
      CFTypeRef data=IORegistryEntryCreateCFProperty(entry,CFSTR("voltage-states9"),kCFAllocatorDefault,0);
      if(data && CFGetTypeID(data)==CFDataGetTypeID()) {
        CFDataRef d=(CFDataRef)data; const uint8_t *bytes=CFDataGetBytePtr(d);
        for(CFIndex offset=0;offset+8<=CFDataGetLength(d);offset+=8) {
          uint32_t hz=0; memcpy(&hz,bytes+offset,4);
          [result addObject:@(hz/1e6)];
        }
      }
      if(data) CFRelease(data);
    }
    IOObjectRelease(entry);
  }
  IOObjectRelease(iter); return result;
}

static BOOL loadIR(void) {
  ir.handle=dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY|RTLD_LOCAL);
  if (!ir.handle) return NO;
#define LOAD(field,sym) ir.field=(void *)dlsym(ir.handle,"IOReport" sym); if (!ir.field) return NO
  LOAD(copy,"CopyChannelsInGroup"); LOAD(subscribe,"CreateSubscription");
  LOAD(sample,"CreateSamples"); LOAD(delta,"CreateSamplesDelta");
  LOAD(name,"ChannelGetChannelName"); LOAD(subgroup,"ChannelGetSubGroup");
  LOAD(unit,"ChannelGetUnitLabel"); LOAD(integer,"SimpleGetIntegerValue");
  LOAD(states,"StateGetCount"); LOAD(stateName,"StateGetNameForIndex");
  LOAD(residency,"StateGetResidency");
#undef LOAD
  return YES;
}

static BOOL wanted(const char *label, NSString *name) {
  if (!strcmp(label,"gpu")) return [name isEqualToString:@"GPUPH"];
  if (!strcmp(label,"cpustates")) return [@[@"ECPU",@"PCPU",@"PCPU1"] containsObject:name];
  if (!strcmp(label,"power")) return [@[@"GPU Energy",@"CPU Energy",@"DRAM0",@"ANE0"] containsObject:name];
  if (!strcmp(label,"bandwidth")) return [name containsString:@"DCS"];
  if (!strcmp(label,"pmp")) return [name containsString:@"RD+WR"] || [name containsString:@"AMCC"];
  return NO;
}

static NSDictionary *setupIR(IRGroup *g, BOOL inspect) {
  CFMutableDictionaryRef all=ir.copy(g->group,g->subgroup,0,0,0);
  if (!all) { strcpy(g->error,"enumeration_failed"); return @{ @"status":@"unavailable", @"reason":@"enumeration_failed" }; }
  CFArrayRef entries=CFDictionaryGetValue(all,CFSTR("IOReportChannels"));
  g->enumerated=entries ? CFArrayGetCount(entries) : 0;
  NSMutableArray *allNames=[NSMutableArray array];
  CFMutableArrayRef picked=CFArrayCreateMutable(kCFAllocatorDefault,0,&kCFTypeArrayCallBacks);
  for (CFIndex i=0; entries && i<CFArrayGetCount(entries); i++) {
    CFDictionaryRef item=CFArrayGetValueAtIndex(entries,i);
    NSString *name=s(ir.name(item));
    if (inspect) [allNames addObject:@{ @"name":name, @"subgroup":s(ir.subgroup(item)), @"unit":s(ir.unit(item)) }];
    if (unfiltered || wanted(g->label,name)) CFArrayAppendValue(picked,item);
  }
  g->selected=CFArrayGetCount(picked);
  NSMutableDictionary *result=[@{ @"status":@"unavailable", @"enumerated":@(g->enumerated), @"selected":@(g->selected) } mutableCopy];
  if (inspect) result[@"channels"]=allNames;
  if (!g->selected) { strcpy(g->error,"no_selected_channels"); result[@"reason"]=@"no_selected_channels"; CFRelease(picked); CFRelease(all); return result; }
  CFMutableDictionaryRef desired=CFDictionaryCreateMutableCopy(kCFAllocatorDefault,0,all);
  CFDictionarySetValue(desired,CFSTR("IOReportChannels"),picked);
  CFRelease(picked); CFRelease(all);
  // IOReportCreateSubscription takes ownership of desired on this OS. Do not release it.
  g->subscription=ir.subscribe(NULL,desired,&g->subscribed,0,NULL);
  if (!g->subscription || !g->subscribed) {
    strcpy(g->error,"subscription_failed"); result[@"reason"]=@"subscription_failed"; return result;
  }
  CFArrayRef accepted=CFDictionaryGetValue(g->subscribed,CFSTR("IOReportChannels"));
  g->subscribedCount=accepted ? CFArrayGetCount(accepted) : 0;
  result[@"subscribed"]=@(g->subscribedCount);
  g->previous=ir.sample(g->subscription,g->subscribed,NULL);
  g->previousTime=nowSeconds();
  if (!g->previous) { strcpy(g->error,"initial_sample_failed"); result[@"reason"]=@"initial_sample_failed"; return result; }
  result[@"status"]=@"measured"; return result;
}

static NSDictionary *sampleIR(IRGroup *g, double nominalInterval) {
  if (!g->subscription) return @{ @"status":@"unavailable", @"reason":@(g->error) };
  CFDictionaryRef current=ir.sample(g->subscription,g->subscribed,NULL);
  double timestamp=nowSeconds();
  if (!current) {
    if (g->previous) { CFRelease(g->previous); g->previous=NULL; }
    g->resetPending=YES;
    return @{ @"status":@"invalid", @"reason":@"sample_failed", @"source":@"IOReport" };
  }
  if (!g->previous) {
    g->previous=current; g->previousTime=timestamp; g->resetPending=NO;
    return @{ @"status":@"unavailable", @"reason":@"baseline_reestablished", @"source":@"IOReport" };
  }
  double window=timestamp-g->previousTime;
  if (!isfinite(window) || window<=0 || window>fmax(30.0,nominalInterval*10.0)) {
    CFRelease(g->previous); g->previous=current; g->previousTime=timestamp; g->resetPending=NO;
    return @{ @"status":@"stale", @"reason":@"invalid_or_long_window", @"window_s":@(window), @"source":@"IOReport" };
  }
  CFDictionaryRef delta=ir.delta(g->previous,current,NULL);
  CFRelease(g->previous); g->previous=current; g->previousTime=timestamp;
  if (!delta) { CFRelease(g->previous); g->previous=NULL; g->resetPending=YES;
    return @{ @"status":@"invalid", @"reason":@"delta_failed", @"window_s":@(window), @"source":@"IOReport" }; }
  CFArrayRef entries=CFDictionaryGetValue(delta,CFSTR("IOReportChannels"));
  NSMutableArray *values=[NSMutableArray array];
  BOOL invalid=NO; long changing=0;
  for (CFIndex i=0; entries && i<CFArrayGetCount(entries); i++) {
    CFDictionaryRef item=CFArrayGetValueAtIndex(entries,i);
    NSMutableDictionary *v=[@{ @"name":s(ir.name(item)), @"unit":s(ir.unit(item)) } mutableCopy];
    int32_t states=ir.states(item);
    if (states>0 && states<128) {
      NSMutableArray *a=[NSMutableArray array];
      for (int32_t j=0;j<states;j++) {
        int64_t n=ir.residency(item,j);
        if (n==INT64_MIN || n<0) invalid=YES;
        if (n>0) changing++;
        [a addObject:@{ @"state":s(ir.stateName(item,j)), @"ticks":@(n) }];
      }
      v[@"states"]=a;
    } else {
      int64_t n=ir.integer(item,NULL);
      if (n==INT64_MIN || n<0) invalid=YES;
      if (n>0) changing++;
      v[@"delta"]=@(n);
    }
    if (invalid) v[@"status"]=@"invalid";
    else if (!strcmp(g->label,"power") && ![v[@"name"] isEqualToString:@"GPU Energy"])
      { v[@"status"]=@"unavailable"; v[@"reason"]=@"unvalidated_energy_channel"; }
    else v[@"status"]=@"measured";
    [values addObject:v];
  }
  CFRelease(delta);
  NSMutableDictionary *result=[@{ @"status":invalid?@"invalid":@"measured", @"source":@"IOReport",
            @"window_s":@(window), @"channels":values,
            @"nonzero_values":@(changing), @"subscribed":@(g->subscribedCount) } mutableCopy];
  if(!strcmp(g->label,"gpu")) {
    NSArray *states=nil; int matches=0;
    for (NSDictionary *v in values) if ([v[@"name"] isEqualToString:@"GPUPH"]) {
      matches++; if ([v[@"unit"] isEqualToString:@"24Mticks"]) states=v[@"states"];
    }
    double all=0,active=0,weighted=0; BOOL mapped=matches==1 && [states isKindOfClass:NSArray.class] && states.count==16 && gpuFreqs.count>1 && !invalid;
    NSMutableSet *names=[NSMutableSet set];
    for(NSDictionary *state in states) {
      int64_t ticks=[state[@"ticks"] longLongValue]; NSString *name=state[@"state"];
      if(ticks<0 || [names containsObject:name]) { mapped=NO; continue; }
      [names addObject:name];
      all+=ticks;
      if([name isEqualToString:@"OFF"]) continue;
      active+=ticks;
      if([name hasPrefix:@"P"]) {
        NSString *number=[name substringFromIndex:1]; NSInteger index=number.integerValue;
        if (![[NSString stringWithFormat:@"%ld",(long)index] isEqualToString:number] || index<1 || index>15) mapped=NO;
        if(index>0 && index<(NSInteger)gpuFreqs.count) weighted+=ticks*gpuFreqs[index].doubleValue;
        else if(ticks>0) mapped=NO;
      } else if(ticks>0) mapped=NO;
    }
    if (![names containsObject:@"OFF"]) mapped=NO;
    for (int index=1;index<=15;index++) if (![names containsObject:[NSString stringWithFormat:@"P%d",index]]) mapped=NO;
    if (all<=0 || !isfinite(active/all) || active>all) mapped=NO;
    result[@"active_ratio"]=mapped?@(active/all):[NSNull null];
    result[@"weighted_active_frequency_mhz"]=mapped&&active>0&&isfinite(weighted/active)?@(weighted/active):[NSNull null];
    result[@"frequency_status"]=mapped&&active>0?@"estimated":@"unavailable";
    if (!mapped) { result[@"status"]=@"invalid"; result[@"reason"]=@"gpu_state_or_unit_mismatch";
      CFRelease(g->previous); g->previous=NULL; g->resetPending=YES; }
  }
  if (!strcmp(g->label,"power")) {
    NSDictionary *channel=nil; int matches=0;
    for (NSDictionary *v in values) if ([v[@"name"] isEqualToString:@"GPU Energy"]) { channel=v; matches++; }
    int64_t delta=[channel[@"delta"] longLongValue]; double watts=delta*1e-9/window;
    BOOL valid=matches==1 && [channel[@"unit"] isEqualToString:@"nJ"] && !invalid &&
      delta>=0 && isfinite(watts) && watts<=1000;
    result[@"gpu_estimated_w"]=valid?@(watts):[NSNull null];
    result[@"gpu_power_status"]=valid?@"estimated":@"invalid";
    result[@"cpu_power_status"]=@"unavailable"; result[@"dram_power_status"]=@"unavailable";
    if (!valid) { result[@"status"]=@"invalid"; result[@"reason"]=@"gpu_energy_unit_channel_or_delta";
      CFRelease(g->previous); g->previous=NULL; g->resetPending=YES; }
  }
  if (!strcmp(g->label,"bandwidth")) {
    double traffic=0; BOOL valid=!invalid;
    for (NSString *name in @[@"GFX DCS RD",@"GFX DCS WR"]) {
      int matches=0; NSDictionary *found=nil;
      for (NSDictionary *v in values) if ([v[@"name"] isEqualToString:name]) { matches++; found=v; }
      if (matches!=1 || ![found[@"unit"] isEqualToString:@"B"] || [found[@"delta"] longLongValue]<0) valid=NO;
      else traffic+=[found[@"delta"] doubleValue];
    }
    double rate=traffic/window/1e9;
    if (!isfinite(rate) || rate>2000) valid=NO;
    result[@"gfx_dcs_traffic_gbs"]=valid?@(rate):[NSNull null];
    result[@"traffic_status"]=valid?@"estimated":@"invalid";
    result[@"v01_approved"]=@NO;
    if (!valid) { result[@"status"]=@"invalid"; result[@"reason"]=@"gfx_channel_unit_or_delta";
      CFRelease(g->previous); g->previous=NULL; g->resetPending=YES; }
  }
  if (invalid && g->previous) { CFRelease(g->previous); g->previous=NULL; g->resetPending=YES; }
  return result;
}

static uint32_t fourcc(const char *key) {
  return ((uint32_t)(uint8_t)key[0]<<24)|((uint32_t)(uint8_t)key[1]<<16)|
         ((uint32_t)(uint8_t)key[2]<<8)|(uint8_t)key[3];
}
typedef struct { char major,minor,build,reserved; uint16_t release; } SMCVers;
typedef struct { uint16_t version,length; uint32_t cpu,gpu,mem; } SMCLimit;
typedef struct { uint32_t size,type; uint8_t attributes; } SMCInfo;
typedef struct { uint32_t key; SMCVers vers; SMCLimit limit; SMCInfo info;
  uint8_t result,status,command; uint32_t data32; uint8_t bytes[32]; } SMCRequest;
static io_connect_t smcConnection=0;
static kern_return_t smcOpenResult=KERN_SUCCESS;
static NSMutableDictionary *smcCache;
static BOOL smcOpen(void) {
  io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
  if (!service) { smcOpenResult=KERN_NOT_FOUND; return NO; }
  kern_return_t kr=IOServiceOpen(service,mach_task_self(),0,&smcConnection);
  smcOpenResult=kr;
  IOObjectRelease(service); smcCache=[NSMutableDictionary dictionary]; return kr==KERN_SUCCESS;
}
static NSDictionary *smcRead(const char *key) {
  if (!smcConnection) return @{ @"status":@"unavailable" };
  NSString *k=[NSString stringWithUTF8String:key];
  NSDictionary *cached=smcCache[k];
  uint32_t size=cached ? [cached[@"size"] unsignedIntValue] : 0;
  uint32_t type=cached ? [cached[@"type"] unsignedIntValue] : 0;
  SMCRequest in={0},out={0}; size_t outSize=sizeof(out); in.key=fourcc(key);
  if (!cached) {
    in.command=9;
    kern_return_t kr=IOConnectCallStructMethod(smcConnection,2,&in,sizeof(in),&out,&outSize);
    if (kr!=KERN_SUCCESS || out.result || out.info.size==0 || out.info.size>32)
      return @{ @"status":@"unavailable", @"reason":@"key_info_failed", @"kr":@(kr), @"smc_result":@(out.result), @"size":@(out.info.size) };
    size=out.info.size; type=out.info.type;
    smcCache[k]=@{ @"size":@(size), @"type":@(type) };
  }
  memset(&in,0,sizeof(in)); memset(&out,0,sizeof(out)); outSize=sizeof(out);
  in.key=fourcc(key); in.info.size=size; in.command=5;
  kern_return_t kr=IOConnectCallStructMethod(smcConnection,2,&in,sizeof(in),&out,&outSize);
  if (kr!=KERN_SUCCESS || out.result) return @{ @"status":@"invalid", @"reason":@"read_failed", @"kr":@(kr), @"smc_result":@(out.result) };
  float value=0;
  if (type==fourcc("flt ") && size==4) memcpy(&value,out.bytes,4);
  else if (type==fourcc("sp78") && size==2) value=(int16_t)((out.bytes[0]<<8)|out.bytes[1])/256.0f;
  else return @{ @"status":@"unavailable", @"reason":@"unsupported_encoding", @"type":@(type) };
  if (!isfinite(value) || value<0 || value>125) return @{ @"status":@"invalid", @"reason":@"sensor_range_or_encoding" };
  return @{ @"status":@"measured", @"source":@"AppleSMC", @"unit":@"C",
    @"celsius":@(value), @"encoding":type==fourcc("flt ")?@"flt":@"sp78" };
}

static atomic_int pressureEvents;
static atomic_int pressureFlag;
static dispatch_source_t pressureSource;
static NSString *pressureName(int n) { return n==DISPATCH_MEMORYPRESSURE_NORMAL?@"normal":n==DISPATCH_MEMORYPRESSURE_WARN?@"warning":n==DISPATCH_MEMORYPRESSURE_CRITICAL?@"critical":@"unknown"; }
static void pressureStart(void) {
  pressureSource=dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE,0,
    DISPATCH_MEMORYPRESSURE_NORMAL|DISPATCH_MEMORYPRESSURE_WARN|DISPATCH_MEMORYPRESSURE_CRITICAL,
    dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
  if (pressureSource) {
    dispatch_source_set_event_handler(pressureSource, ^{ atomic_store(&pressureFlag,(int)dispatch_source_get_data(pressureSource)); atomic_fetch_add(&pressureEvents,1); });
    dispatch_resume(pressureSource);
  }
}

static uint32_t previousTicks[64][CPU_STATE_MAX]; static natural_t previousCount=0;
static double previousCPUTime=0;
static NSDictionary *cpuRead(void) {
  natural_t count=0; processor_info_array_t p=NULL; mach_msg_type_number_t words=0;
  kern_return_t kr=host_processor_info(hostPort,PROCESSOR_CPU_LOAD_INFO,&count,&p,&words);
  double timestamp=nowSeconds();
  if (kr!=KERN_SUCCESS || count==0 || count>64 || words<count*CPU_STATE_MAX || !p) {
    if (p) vm_deallocate(mach_task_self(),(vm_address_t)p,words*sizeof(integer_t));
    previousCount=0; previousCPUTime=0;
    return @{ @"status":@"invalid", @"source":@"host_processor_info", @"kr":@(kr) };
  }
  NSMutableArray *cores=[NSMutableArray array]; double sum=0,pSum=0,eSum=0; int pn=0,en=0;
  BOOL valid=previousCount==count && previousCPUTime>0 && timestamp>previousCPUTime;
  for (natural_t i=0;i<count;i++) {
    uint64_t total=0,busy=0;
    for(int j=0;j<CPU_STATE_MAX;j++) {
      uint32_t cur=(uint32_t)p[i*CPU_STATE_MAX+j];
      uint32_t diff=cur-previousTicks[i][j]; previousTicks[i][j]=cur;
      total+=diff; if(j!=CPU_STATE_IDLE) busy+=diff;
    }
    double u=total ? (double)busy/total : 0;
    if (!total) valid=NO;
    [cores addObject:@(u)]; sum+=u;
    if (peTopologyValid && count==10) { if (expectedCoreType[i]==0) { eSum+=u;en++; } else { pSum+=u;pn++; } }
  }
  vm_deallocate(mach_task_self(),(vm_address_t)p,words*sizeof(integer_t));
  double window=timestamp-previousCPUTime; previousCount=count; previousCPUTime=timestamp;
  BOOL grouped=valid && peTopologyValid && count==10 && pn==8 && en==2;
  return @{ @"status":valid?@"measured":@"unavailable", @"source":@"host_processor_info",
            @"window_s":valid?@(window):[NSNull null], @"unit":@"ratio",
            @"total":valid?@(sum/count):[NSNull null], @"p":grouped?@(pSum/pn):[NSNull null],
            @"e":grouped?@(eSum/en):[NSNull null], @"pe_status":grouped?@"measured":@"unavailable",
            @"cores":valid?cores:@[] };
}

static uint64_t previousSwapins=0, previousSwapouts=0;
static double previousVMTime=0;
static NSDictionary *vmRead(void) {
  vm_statistics64_data_t v={0}; mach_msg_type_number_t n=HOST_VM_INFO64_COUNT;
  kern_return_t kr=host_statistics64(hostPort,HOST_VM_INFO64,(host_info64_t)&v,&n);
  double timestamp=nowSeconds();
  if(kr!=KERN_SUCCESS || n<HOST_VM_INFO64_COUNT) {
    previousVMTime=0;
    return @{ @"status":@"invalid", @"source":@"host_statistics64", @"kr":@(kr) };
  }
  uint64_t page=(uint64_t)vm_kernel_page_size;
  BOOL rateValid=previousVMTime>0 && timestamp>previousVMTime &&
    timestamp-previousVMTime<=30 && v.swapins>=previousSwapins && v.swapouts>=previousSwapouts;
  double window=timestamp-previousVMTime;
  uint64_t inDelta=rateValid?v.swapins-previousSwapins:0, outDelta=rateValid?v.swapouts-previousSwapouts:0;
  previousVMTime=timestamp; previousSwapins=v.swapins; previousSwapouts=v.swapouts;
  return @{ @"status":physicalBytes&&page?@"measured":@"invalid", @"source":@"HOST_VM_INFO64",
    @"physical_bytes":@(physicalBytes),
    @"page_bytes":@(page), @"free_bytes":@(v.free_count*page),
    @"active_bytes":@(v.active_count*page), @"inactive_bytes":@(v.inactive_count*page),
    @"wired_bytes":@(v.wire_count*page), @"compressed_bytes":@(v.compressor_page_count*page),
    @"swapins_cumulative":@(v.swapins), @"swapouts_cumulative":@(v.swapouts),
    @"swap_activity":@{ @"status":rateValid?@"measured":@"unavailable", @"source":@"HOST_VM_INFO64",
       @"unit":@"pages/s", @"window_s":rateValid?@(window):[NSNull null],
       @"swapin_pages_per_s":rateValid?@(inDelta/window):[NSNull null],
       @"swapout_pages_per_s":rateValid?@(outDelta/window):[NSNull null] },
    @"pageins_cumulative":@(v.pageins), @"pageouts_cumulative":@(v.pageouts) };
}
static NSDictionary *swapRead(void) {
  struct xsw_usage x={0}; size_t n=sizeof(x); errno=0;
  if(sysctlbyname("vm.swapusage",&x,&n,NULL,0)) return @{ @"status":errno==EPERM?@"blocked":@"unavailable", @"errno":@(errno) };
  return @{ @"status":@"measured", @"source":@"vm.swapusage", @"unit":@"B",
    @"used_bytes":@(x.xsu_used), @"total_bytes":@(x.xsu_total) };
}
static NSDictionary *pressureRead(void) {
  int v=0; size_t n=sizeof(v); errno=0;
  int rc=sysctlbyname("kern.memorystatus_vm_pressure_level",&v,&n,NULL,0);
  int events=atomic_load(&pressureEvents);
  return @{ @"current":rc==0?@{ @"status":@"measured", @"raw":@(v), @"source":@"kern.memorystatus_vm_pressure_level" }:@{ @"status":errno==EPERM?@"blocked":@"unavailable", @"errno":@(errno) },
    @"events":@(events), @"event_state":events?pressureName(atomic_load(&pressureFlag)):@"unknown",
    @"event_source":pressureSource?@"active":@"unavailable" };
}
static NSDictionary *selfRead(void) {
  struct rusage r={0}; getrusage(RUSAGE_SELF,&r);
  double cpu=r.ru_utime.tv_sec+r.ru_utime.tv_usec/1e6+r.ru_stime.tv_sec+r.ru_stime.tv_usec/1e6;
  struct rusage_info_v6 info={0}; int rc=proc_pid_rusage(getpid(),RUSAGE_INFO_V6,(rusage_info_t *)&info);
  mach_port_urefs_t refs=0; kern_return_t portKr=hostPort?mach_port_get_refs(mach_task_self(),hostPort,MACH_PORT_RIGHT_SEND,&refs):KERN_INVALID_ARGUMENT;
  pid_t children[32]={0}; int childBytes=proc_listchildpids(getpid(),children,sizeof(children));
  return @{ @"cpu_seconds":@(cpu), @"resident_bytes":rc==0?@(info.ri_resident_size):[NSNull null],
    @"host_port_send_refs":portKr==KERN_SUCCESS?@(refs):[NSNull null],
    @"child_process_count":childBytes>=0?@(childBytes/(int)sizeof(pid_t)):[NSNull null],
    @"package_idle_wakeups":rc==0?@(info.ri_pkg_idle_wkups):[NSNull null],
    @"interrupt_wakeups":rc==0?@(info.ri_interrupt_wkups):[NSNull null],
    @"voluntary_context_switches":@(r.ru_nvcsw), @"involuntary_context_switches":@(r.ru_nivcsw) };
}

static void emit(NSDictionary *d) {
  NSError *error=nil; NSData *data=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingFragmentsAllowed error:&error];
  if(data) { fwrite(data.bytes,1,data.length,stdout); fputc('\n',stdout); fflush(stdout); }
  else { fprintf(stderr,"JSON error: %s\n",error.localizedDescription.UTF8String); exit(4); }
}
static NSString *isoDate(void) { return [NSISO8601DateFormatter stringFromDate:[NSDate date] timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0] formatOptions:NSISO8601DateFormatWithInternetDateTime|NSISO8601DateFormatWithFractionalSeconds]; }
static NSString *thermalName(void) {
  switch(NSProcessInfo.processInfo.thermalState) { case NSProcessInfoThermalStateNominal:return @"nominal";
    case NSProcessInfoThermalStateFair:return @"fair"; case NSProcessInfoThermalStateSerious:return @"serious";
    case NSProcessInfoThermalStateCritical:return @"critical"; }
  return @"unknown";
}

static int probe(NSString *groups, double interval, int samples, BOOL inspect, BOOL stability) {
  NSSet *enabled=[NSSet setWithArray:[groups componentsSeparatedByString:@","]];
  hostPort=mach_host_self();
  if (!hostPort) { fprintf(stderr,"mach_host_self failed\n"); return 3; }
  size_t memSize=sizeof(physicalBytes);
  if (sysctlbyname("hw.memsize",&physicalBytes,&memSize,NULL,0)!=0 || memSize!=sizeof(physicalBytes)) physicalBytes=0;
  BOOL useIR=[enabled intersectsSet:[NSSet setWithArray:@[@"gpu",@"power",@"bandwidth",@"cpustates",@"pmp",@"ane"]]];
  BOOL irOK=useIR ? loadIR() : NO;
  NSMutableDictionary *setup=[NSMutableDictionary dictionary];
  setup[@"topology"]=checkTopology();
  if([enabled containsObject:@"gpu"]) { gpuFreqs=readGPUFreqs(); setup[@"gpu_dvfs_mhz"]=gpuFreqs; }
  for(size_t i=0;i<sizeof(irGroups)/sizeof(irGroups[0]);i++) {
    IRGroup *g=&irGroups[i];
    if (![enabled containsObject:@(g->label)] && !(strcmp(g->label,"power")==0 && [enabled containsObject:@"ane"])) continue;
    setup[@(g->label)]=irOK?setupIR(g,inspect):@{ @"status":@"unavailable", @"reason":@"library_missing" };
  }
  if([enabled containsObject:@"temperature"]) { BOOL ok=smcOpen(); setup[@"smc"]=@{ @"status":ok?@"open":@"unavailable", @"kr":@(smcOpenResult) }; }
  if([enabled containsObject:@"memory"]) pressureStart();
  if([enabled containsObject:@"public"]) (void)cpuRead();
  if([enabled containsObject:@"public"] || [enabled containsObject:@"memory"]) (void)vmRead();
  emit(@{ @"kind":@"setup", @"timestamp":isoDate(), @"groups":groups, @"interval_s":@(interval), @"ioreport":setup,
          @"pid":@(getpid()), @"stability":@(stability), @"source":@"step2.6-probe" });
  const int warmupSamples=stability?15:0;
  const int segmentSamples[6]={60,24,60,24,60,24};
  int totalSamples=stability?warmupSamples+252:samples;
  double next=nowSeconds()+(stability?2.0:interval), lastSampleTime=0;
  int previousSegment=-1;
  for(int i=0;i<totalSamples;i++) {
    @autoreleasepool {
    int segment=-1, segmentIndex=-1; double currentInterval=interval;
    if (stability) {
      currentInterval=2.0;
      if (i>=warmupSamples) {
        int relative=i-warmupSamples;
        for (int j=0;j<6;j++) {
          if (relative<segmentSamples[j]) { segment=j; segmentIndex=relative; break; }
          relative-=segmentSamples[j];
        }
        currentInterval=segment%2==0?2.0:5.0;
      }
    }
    if (segment!=previousSegment && segment>=0) {
      next=lastSampleTime+currentInterval;
      emit(@{ @"kind":@"segment_start", @"segment":@(segment), @"interval_s":@(currentInterval),
              @"monotonic_s":@(nowSeconds()), @"self":selfRead() });
      previousSegment=segment;
    }
    BOOL injected=stability && segment==2 && segmentIndex==30;
    if (injected) usleep(6200000);
    double wait=next-nowSeconds(); if(wait>0) usleep((useconds_t)(wait*1e6));
    double start=nowSeconds(); NSMutableDictionary *v=[NSMutableDictionary dictionary];
    if([enabled containsObject:@"public"]) { v[@"cpu"]=cpuRead(); v[@"thermal_state"]=@{ @"status":@"measured", @"source":@"ProcessInfo.thermalState", @"value":thermalName() }; }
    if([enabled containsObject:@"public"] || [enabled containsObject:@"memory"]) v[@"vm"]=vmRead();
    if([enabled containsObject:@"memory"]) { v[@"swap"]=swapRead(); v[@"pressure"]=pressureRead(); }
    if([enabled containsObject:@"temperature"]) {
      NSMutableDictionary *t=[NSMutableDictionary dictionary];
      NSArray<NSString *> *keys=inspect?@[@"Tp09",@"Tp01",@"Tp05",@"Tg05",@"Tg0D",@"Tg0P"]:@[@"Tp05",@"Tg05"];
      for(NSString *key in keys)
        t[key]=smcRead(key.UTF8String);
      v[@"temperature"]=t;
    }
    NSMutableDictionary *rs=[NSMutableDictionary dictionary];
    for(size_t j=0;j<sizeof(irGroups)/sizeof(irGroups[0]);j++) {
      IRGroup *g=&irGroups[j];
      if([enabled containsObject:@(g->label)] || (!strcmp(g->label,"power") && [enabled containsObject:@"ane"]))
        rs[@(g->label)]=sampleIR(g,currentInterval);
    }
    if(rs.count) v[@"ioreport"]=rs;
    double latency=nowSeconds()-start;
    NSMutableDictionary *row=[@{ @"kind":@"sample", @"timestamp":isoDate(), @"index":@(i),
      @"nominal_interval_s":@(currentInterval), @"monotonic_s":@(start),
      @"tick_window_s":lastSampleTime>0?@(start-lastSampleTime):[NSNull null],
      @"phase":stability?(segment>=0?@"segment":@"warmup"):@"standard",
      @"sampling_latency_ms":@(latency*1000), @"values":v, @"self":selfRead() } mutableCopy];
    if (segment>=0) { row[@"segment"]=@(segment); row[@"segment_index"]=@(segmentIndex); }
    if (injected) row[@"injected_delay_s"]=@6.2;
    emit(row);
    lastSampleTime=start;
    if (segment>=0 && segmentIndex==segmentSamples[segment]-1)
      emit(@{ @"kind":@"segment_end", @"segment":@(segment), @"monotonic_s":@(nowSeconds()), @"self":selfRead() });
    next=nowSeconds()+currentInterval;
    }
  }
  if (smcConnection) IOServiceClose(smcConnection);
  if (pressureSource) dispatch_source_cancel(pressureSource);
  if (hostPort) { mach_port_deallocate(mach_task_self(),hostPort); hostPort=MACH_PORT_NULL; }
  return 0;
}

static int loadWork(NSString *kind, double duration) {
  double end=nowSeconds()+duration;
  if([kind hasPrefix:@"cpu"]) {
    int threads=[kind isEqualToString:@"cpu-multi"]?10:1;
    dispatch_apply(threads,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t n){
      volatile double x=n+1; while(nowSeconds()<end) { for(int j=0;j<10000;j++) x=x*1.00000001+0.000001; }
    }); return 0;
  }
  id<MTLDevice> device=MTLCreateSystemDefaultDevice(); if(!device) return 2;
  BOOL stream=[kind isEqualToString:@"gpu-bandwidth"];
  NSString *source=stream
    ? @"#include <metal_stdlib>\nusing namespace metal; kernel void burn(device float4 *a [[buffer(0)]], device float4 *b [[buffer(1)]], uint id [[thread_position_in_grid]]) { b[id]=a[id]*1.00001f+float4(0.0001f); }"
    : @"#include <metal_stdlib>\nusing namespace metal; kernel void burn(device float *a [[buffer(0)]], uint id [[thread_position_in_grid]]) { float x=a[id]; for (int i=0;i<800;i++) x=sin(x)*1.00001f+0.0001f; a[id]=x; }";
  NSError *error=nil; id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
  if(!library){fprintf(stderr,"Metal compile: %s\n",error.localizedDescription.UTF8String);return 2;}
  id<MTLComputePipelineState> pipeline=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"burn"] error:&error];
  if(!pipeline){fprintf(stderr,"Metal pipeline: %s\n",error.localizedDescription.UTF8String);return 2;}
  id<MTLBuffer> buffer=[device newBufferWithLength:stream?64*1024*1024:1024*1024*sizeof(float) options:MTLResourceStorageModeShared];
  id<MTLBuffer> output=stream?[device newBufferWithLength:64*1024*1024 options:MTLResourceStorageModeShared]:nil;
  id<MTLCommandQueue> queue=[device newCommandQueue];
  int launches=0;
  while(nowSeconds()<end) {
    @autoreleasepool {
      id<MTLCommandBuffer> command=[queue commandBuffer]; id<MTLComputeCommandEncoder> encoder=[command computeCommandEncoder];
      [encoder setComputePipelineState:pipeline]; [encoder setBuffer:buffer offset:0 atIndex:0];
      if(stream) [encoder setBuffer:output offset:0 atIndex:1];
      [encoder dispatchThreads:MTLSizeMake(stream?4*1024*1024:1024*1024,1,1) threadsPerThreadgroup:MTLSizeMake(256,1,1)];
      [encoder endEncoding]; [command commit]; [command waitUntilCompleted]; launches++;
    }
    if([kind isEqualToString:@"gpu-moderate"]) usleep(5000);
  }
  fprintf(stderr,"Metal launches=%d\n",launches); return 0;
}

int main(int argc,const char **argv) { @autoreleasepool {
  NSString *groups=@"public"; NSString *load=nil; double interval=2,duration=10; int samples=5; BOOL inspect=NO,stability=NO;
  for(int i=1;i<argc;i++) {
    if(!strcmp(argv[i],"--groups") && i+1<argc) groups=@(argv[++i]);
    else if(!strcmp(argv[i],"--interval") && i+1<argc) interval=atof(argv[++i]);
    else if(!strcmp(argv[i],"--samples") && i+1<argc) samples=atoi(argv[++i]);
    else if(!strcmp(argv[i],"--inspect")) inspect=YES;
    else if(!strcmp(argv[i],"--stability")) stability=YES;
    else if(!strcmp(argv[i],"--unfiltered")) unfiltered=YES;
    else if(!strcmp(argv[i],"--load") && i+1<argc) load=@(argv[++i]);
    else if(!strcmp(argv[i],"--duration") && i+1<argc) duration=atof(argv[++i]);
    else { fprintf(stderr,"usage: telemetry-probe [--groups public,gpu,power,temperature,memory,bandwidth,cpustates,pmp,ane] [--interval seconds] [--samples count] [--inspect] [--load cpu-single|cpu-multi|gpu-moderate|gpu-heavy|gpu-bandwidth --duration seconds]\n"); return 2; }
  }
  if(load) return loadWork(load,duration);
  if(interval<=0 || samples<1) return 2;
  return probe(groups,interval,samples,inspect,stability);
} }

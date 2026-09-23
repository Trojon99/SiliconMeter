# Step 3.0 architecture — menu-bar telemetry v0.1

## Boundary

`app/ComputeMonitor.swift` owns the AppKit status item, compact popover, typed in-process `Metric` and `TelemetrySnapshot`, and one `TelemetryService`. The backend is one `TelemetryBackend` instance, confined to its serial utility queue. Both UI surfaces consume the same snapshot; neither polls hardware. `app/TelemetryBackend.m` implements the measured Mach, IOReport, AppleSMC, IOKit, and sysctl reads. This preserves the validated low-level ABI and counter logic without moving the experiment's JSON output, Metal load generator, bandwidth diagnostics, or process measurement machinery into the app.

Swift provides the public ProcessInfo thermal state and its change notification. Objective-C is retained for IOReport's private C ABI, AppleSMC's packed request structure, and explicit Mach/IOKit resource lifetimes. A narrow Objective-C header returns small metric dictionaries. Swift immediately converts these to structured `Metric` values with value, unit, observation time, optional monotonic measurement window, quality, source, and reason. This snapshot can later feed a logging consumer; no logging exists now.

## Collection and validity

The service owns one one-shot Dispatch timer. It rearms **after** collection, approximately every 2 seconds, with no catch-up samples. Each fast tick reads total/P/E CPU and GPU activity/weighted active frequency. Every third tick also reads GPU energy-derived power, raw VM classifications, swap usage and activity, memory pressure, and `Tp05`/`Tg05` temperatures, approximately every 6 seconds. Initial slow readings are taken on startup. Thermal changes use `ProcessInfo.thermalStateDidChangeNotification`; memory-pressure DispatchSource events request a current-pressure reread. The current pressure sysctl is also refreshed on slow ticks because the event source alone has no trustworthy initial state.

Mach CPU ticks, IOReport residency, GPU Energy nJ, and VM swap page rates use their own actual monotonic delta windows. A missing baseline, read failure, invalid counter, or window over 30 seconds yields unavailable, invalid, or stale status and a fresh baseline as appropriate. No unavailable reading becomes a numeric zero. Snapshot values older than 20 seconds are displayed as stale, except initialization-only physical memory and event-driven thermal state.

Initialization caches physical memory, validated 8 P + 2 E topology, GPU DVFS states, selected IOReport channels/subscriptions, and SMC sensor metadata. P/E results fail closed unless the full M1 Max device-tree and sysctl mapping matches. GPU activity requires unique `GPUPH`, the expected unit and full OFF/P1–P15 state set. Weighted active frequency is an estimate, not an instantaneous clock. GPU power uses only unique `GPU Energy` nJ and is estimated. Temperature names identify specific sensors, not chip maxima. At shutdown the service cancels its timer, removes the thermal observer, cancels pressure events, releases IOReport snapshots/subscriptions, closes AppleSMC and the dynamic library, and deallocates its Mach host-port right. Per-tick autorelease pools bound temporary Foundation objects.

## Distribution and limits

The intended distribution is a Developer ID signed and notarized **non-App-Sandboxed** app, using Hardened Runtime where compatible. This local build is unsigned for distribution and does not attempt notarization. It runs as an ordinary user with no root helper, persistent child process, network call, analytics upload, or disk metric history. The Step 2.5 sandbox test showed IOReport subscriptions and SMC access failed in the tested App Sandbox; Mac App Store compatibility is not the v0.1 target.

IOReport symbols/channels, AppleSMC protocol, device-tree topology properties, GPU DVFS mappings, and the pressure sysctl are undocumented or private and may break across hardware or OS updates. Capability failures remain visible as unavailable. GPU power and weighted frequency have not been externally calibrated. Pressure transition and nonzero swap behavior have not been induced in this step.

GFX DCS/AMC bandwidth remains experimental and is absent from the production collector and UI. CPU/DRAM power, ANE, and process attribution remain deferred. Training Saturation, Headroom, AI analysis, automatic tuning, ML framework integration, SQLite/history, and cloud features are outside Step 3.0.

## Step 3.1 review amendments

See [the independent review](STEP31_REVIEW.md) for the long-run evidence and its
instrumentation limits. Fast and slow results on the same tick now merge before
one main-thread publication. Freshness uses the observation's monotonic uptime,
while Date remains its wall-clock timestamp. A VM read failure invalidates every
VM-derived field immediately; physical memory retains its independent source.
CPU backward jumps are rejected without rejecting small unsigned counter wraps.
Service start is idempotent, and the cross-queue pressure callback uses atomic
copy ownership. IOReport subscription inputs are explicitly released after the
call; Step 3.1 verified that the private function does not consume the caller
reference, correcting the earlier ownership comment. The ordinary build
excludes all Step 3.1 observation hooks.

## Step 3.2 history amendment

`HistoryLogger` consumes the centralized typed snapshot after main-queue publication. The collector performs no extra hardware reads, and the logger's single SQLite writer queue never shares the collector queue. Fast/slow samples and state changes are stored separately with per-metric quality and actual backend windows. A batch is committed approximately every 30 seconds on the existing cadence, with a final synchronous flush during normal AppKit Quit. The versioned local schema and read-only query examples are documented in [HISTORY_SCHEMA.md](HISTORY_SCHEMA.md); implementation and validation are in [STEP32_HISTORY_LOGGING.md](STEP32_HISTORY_LOGGING.md).

# Minimal Monitor v0.1 verification report

This report records the scope recovery, bilingual UI, Network validation, and local verification. The product remains a generic Apple Silicon menu-bar monitor and SQLite recorder. All times in evidence files are UTC.

## A–I. Repository and database recovery

**A. Starting state.** The checkout was `phase3/training-sessions-v0.1` at Step 3.2 commit `78e2fb2`, with 12 Training Session WIP files. The real database was at `~/Library/Application Support/Compute Monitor/telemetry.sqlite3`, `user_version=2`, `integrity_check=ok`, with 8 app runs, 1,418 fast samples, 476 slow samples, 12 events, 97 writer batches, and one experimental session row. The main, WAL, and SHM sizes were 557,056, 0, and 32,768 bytes.

**B. Archive.** The WIP is saved only on `archive/abandoned-training-session-wip` at `7adb5ed` (`wip: archive abandoned training session experiment`). The formal branch does not descend from this commit.

**C. Formal branch.** `phase3/minimal-monitor-v0.1` starts at `78e2fb2`. The previously validated menu-bar label commit `fd82bfa` is an ancestor; it needed no cherry-pick.

**D. Actual v1/v2 difference.** The five core telemetry table definitions and their indexes were identical. The v2 experiment added `training_sessions`, `one_active_training_session`, and `training_sessions_recent`, and advanced `user_version` from 1 to 2. No core table column, trigger, or core index changed.

**E. Formal schema.** v3 represented the minimal monitor after the abandoned experiment, without any active Training Session code. After v3 had already been applied to the real database, the Network addition advanced schema monotonically to v4. v4 appends six columns to `fast_samples`: RX/TX bytes/s, quality, and actual window. New installs create only the five core tables. The old experimental table in an upgraded v2 database is left unused so its existing row is not deleted.

**F–G. Copy migrations.** Before the v3 real-data launch, the initial minimal build migrated a genuine Step 3.2 v1 copy to v3 and a backed-up real v2 copy to v3; both preserved all telemetry rows, passed integrity checks, and appended new telemetry. The current final migration test covers v1→v4, v2→v4, and a backed-up v3→v4. It verifies original rows, legacy-table preservation, integrity, new append behavior, and rejection of malformed or future core schemas.

**H. Real database.** The v2 original and its WAL/SHM were copied to `backups/pre-v3-20260923-234315/` before the v3 launch. After the v3 long run and graceful quit, v3 and its WAL/SHM were copied to `backups/pre-v4-20260923-142214/` before the v4 launch. Each directory also has a consistent SQLite backup and manifest. The real database is now v4 with `integrity_check=ok`.

**I. Row preservation.** Every original v2 telemetry row and every pre-v4 v3 telemetry row was found in the v4 database when compared on original columns. The one legacy experimental row remains unchanged. New Network columns on historical rows are NULL with `unavailable` quality.

## J–R. Minimal monitor

**J. Menu bar.** One primary metric is selected from CPU, GPU, temperature, GPU power, and Network. Each metric/language pair has a fixed measured status-item width. Invalid or unavailable values show `—`; no recording or workload badge is added.

**K. Popover.** Current CPU, GPU, Network, memory, and thermal readings appear with compact History status, database size, Open Data Folder, language choice, and Quit. There is no chart or analysis UI.

**L. History.** One background serial SQLite writer retains the Step 3.2 batch/WAL/UTC/quality behavior and graceful flush. Local SQLite readers can query committed rows. Network uses the same fast sample rows and time axis.

**M. Growth.** Step 3.2 measured 0.572 MB/hour before Network. During the v4 enabled run, the database main file grew 172,032 bytes in 887.1 seconds between read-only size snapshots after A's checkpoint and after B's graceful exit: approximately **0.698 MB/hour**, or 16.75 MB/day, 117.26 MB/7 days, and 502.56 MB/30 days at the same rate. This is a short-window linear projection, not a retention guarantee. Active WAL/SHM size is separate from durable growth.

**N–O. Stability and resources.** The ordinary v3 app ran 900.3 seconds with one PID, 420 additional fast rows, 140 additional slow rows, 28 writer batches, and integrity `ok` at every 30-second check. External `ps` observations gave 0.303% mean CPU of one core; late RSS varied by 0.05 MiB around 93.7 MiB. It had no child process or network socket. The final v4 enabled app then ran 900.01 seconds with 428 fast rows, 143 slow rows, 29 writer batches, a 2.101-second median cadence, 0.368% CPU of one core after warmup, 53.31 MiB final RSS, and 0.22 MiB late RSS range. The different v3 RSS includes an opened popover; the A/B comparison below uses matched closed-popover conditions. v4 integrity was `ok` after graceful exit. UI smoke separately switched all five menu choices and checked live data, width, and popover containment.

**P–Q. Changes and commits.** The product branch contains the UI/localization, v4 migration/history, native Network sampler, tests, and bilingual documentation in `0a2f4f2` (`feat: build bilingual minimal monitor with network telemetry candidate`). `cb5e29b` adds the fixed-width menu bar and AppKit boundary test. The archive commit `7adb5ed` is separate and is not an ancestor of the product branch. This report is committed separately.

**R. Remaining limits.** IOReport/AppleSMC compatibility remains hardware and macOS dependent. Network physical-link filtering is conservative. Controlled download and upload passed as described in AF. A second active physical link, hardware interface transition, and controlled VPN transfer were unavailable, so multi-interface aggregation and VPN double-counting were not runtime-tested. Their filtering and baseline behavior retain synthetic checks.

## S–W. English and Simplified Chinese

**S–T.** `app/Localization.swift` loads `en.lproj` and `zh-Hans.lproj` resources through one localizer. First launch follows the system language for Simplified Chinese and uses English otherwise. A manual choice applies immediately and is saved in `UserDefaults`, outside the telemetry database. Cross-process restart persistence passed in the normal user session.

**U–V.** English and Chinese AppKit smoke tests passed for menu labels, Network/History/popover text, estimated/invalid meanings, live telemetry preservation, fixed status-item width, and control bounds. A separate offscreen layout test passed both languages in the 740-point popover.

**W.** `README.md` and `README.zh-CN.md` link to each other and cover features, metrics, history, privacy, requirements, installation, source build, data location, limits, private API risk, and license with matching structure.

## X–AD. Network RX/TX candidate

**X. Backend.** `NetworkSampler` discovers and filters interfaces via `NET_RT_IFLIST2` / `if_msghdr2`, then reads each selected interface's full 64-bit `ifi_ibytes`/`ifi_obytes` through `IFMIB_IFDATA` and divides deltas by the actual monotonic interval. The initial route-message byte fields wrapped at 4 GiB on this macOS build; AF describes the minimal correctness fix. The sampler runs inside the existing approximately 2-second fast collector tick, without another timer, subprocess, packet capture, or network request. [Darwin sysctl](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/sysctl.3.html) and [Apple's interface-message definition](https://developer.apple.com/documentation/kernel/if_msghdr2) describe the underlying APIs; the installed Apple SDK defines `ifmibdata.ifmd_data` as `if_data64`.

**Y. Filtering.** Eligible interfaces must be up/running, Ethernet-type, and report a positive link rate. The sampler excludes loopback, tunnel, AWDL/LLW, bridge, and known virtual/peer names. It sums separate physical-link deltas and never adds `utun` on top of a lower link. This can omit unusual physical adapters and cannot classify every possible virtual adapter perfectly.

**Z. Correctness.** Native synthetic checks passed baseline, independent RX/TX direction, two-interface sum, measured zero, disappearance/reappearance, counter reset, index/link change, stale-window, and full 64-bit crossing of the 4 GiB boundary. The host had one eligible physical interface in the live two-read check. The 15-minute ordinary run recorded five valid zero/zero windows, supporting idle-zero semantics. Controlled real download and upload later passed in AF, including native, ordinary-app SQLite, and Apple reference comparisons.

**AA. Overhead.** The **same ordinary binary** ran 600.01 seconds with Network disabled and 900.01 seconds enabled, with a 60-second warmup excluded from CPU averages. External libproc measured 0.331% versus 0.368% of one core, an increase of 0.037 percentage points; final RSS was 53.19 versus 53.31 MiB, an increase of 0.12 MiB. Late RSS ranges were 0.19 versus 0.22 MiB. Median fast cadence was 2.100 versus 2.101 seconds; invalid/stale Network counts were zero. The enabled phase had 427 measured rows and one initial unavailable baseline row, including five valid zero/zero windows. A separate 100-read native sampler timing check averaged 1.083 ms (median 0.781 ms, p95 2.969 ms); this is a local system-call timing result, not a power measurement. Network adds no timer, and process snapshots during A and at B start/late B showed no child or network socket. A review-only collector check ran 60 ticks per phase with the same sampling code: mean 3.94 ms disabled and 4.63 ms enabled (0.69 ms difference), median 3.65 and 4.19 ms. This excludes AppKit and SQLite; ordinary-build collector latency cannot be isolated externally. Wakeups and Energy Impact are unavailable. Context switches are recorded but are not wakeups. These sequential A/B runs are subject to ambient-system variation. These long A/B runs preceded the full-64-bit counter fix; AF gives its 100-read timing and ordinary-app cadence check, but does not repeat a full 15-minute A/B.

**AB. History.** `fast_samples` stores `network_rx_bytes_per_sec` and `network_tx_bytes_per_sec` as bytes/s, each with quality and actual window. No eligible interface or fresh baseline means `unavailable` and NULL; measured zero is numeric zero. Old rows keep NULL/unavailable. `docs/HISTORY_SCHEMA.md` has units and read-only SQL examples.

**AC. UI.** English shows Network, Upload, Download; Chinese shows 网络, 上传, 下载. Both menu-bar modes use compact `NET ↑… ↓…`, retaining separate units when TX/RX scales differ. Both languages passed live AppKit and layout smoke checks.

**AD. VPN and multiple interfaces.** Multiple independent eligible interfaces are summed in synthetic tests; no second physical link was available for a live transition. An active `utun` was present on the host but excluded by the filter; no controlled VPN transfer was available to measure double counting empirically.

## AE. Menu-bar width stabilization

The first fixed-width layout removed the external menu-bar jump but right-aligned each value against a maximum slot. The Network maximum included the scientific-notation fallback, so unused slot width appeared *between* `↓`/`↑` and their readings. Short CPU values and unavailable states showed the same problem on a smaller scale.

`StatusTitleLayout` measures and caches ten metric/language layouts and applies a fixed `NSStatusItem.length` only on initialization, metric selection, or language selection. AppKit tabs position the label, arrows, and numeric slots inside that container. The Network path retains its right-aligned RX/TX slots selected by displayed digit-count/unit shape. The scalar path now uses one fixed slot per metric with its value leading-aligned, as detailed below. Numeric text retains the system monospaced-digit font. Per-tick work is a cached width lookup, small coordinate arithmetic, and an attributed-title/accessibility update; there is no glyph/template measurement, timer, sampler, observer, polling, collector cadence change, network-backend change, or SQLite change on that path.

In `2fc1ffc`, the nominal scalar label gap was 5 pt, but right alignment inside the numeric slot put unused width *before* short values. AppKit measured 5.6–22.6 pt visible gaps for CPU/GPU/temperature and 5.7–6.5 pt for GPU Power. Network's requested gaps remain 6 pt `NET→↑`, 3 pt arrow→value, 7 pt TX→`↓`, and 3 pt `↓`→RX; AppKit measured 6.6 pt, 3.9–4.9 pt, 7.0 pt, and 3.9–4.9 pt respectively. Its sampled TX/RX slot widths remain 31 pt for `0 B/s`, 52 pt for `3.4 KB/s`, 60 pt for `56.1 KB/s`, 68 pt for `999.9 KB/s`, 71 pt for `999.9 MB/s`, and 53 pt for `1.0 GB/s`. Network promotes rounded unit boundaries and supports B/s through EB/s with a scientific fallback for unrealistic higher rates.

The long Network A/B in AA predates this UI-only change; its collector and timer paths were not modified for AE.

The real AppKit status-item test measured these fixed external widths in points:

| Language | CPU | GPU | Temp | GPU Power | NET |
|---|---:|---:|---:|---:|---:|
| English | 85 | 86 | 95 | 169 | 249 |
| 简体中文 | 85 | 86 | 87 | 157 | 249 |

Across 88 boundary, unavailable, mixed-scale, and scientific-fallback values, each metric/language pair kept the exact same `statusItem.length` and button frame width; an adjacent real status item stayed at the same screen position after mode-change layout settled and throughout every value change. Same-shape values kept numeric slot endpoints within one point. The requested CPU, GPU, temperature, GPU Power, and Network examples were rendered through a real `NSStatusBarButton` in both languages and visually inspected in [the contact sheet](results/status-visual.png), including all unavailable states. The complete graphical app smoke passed `fixed_width=true`, `chinese=true`, and `english=true` while switching modes/languages and injecting representative live-value changes; its review-only counter confirmed no layout measurement during those value updates or when revisiting a cached pair.

**Scalar-spacing follow-up.** CPU/GPU/Temp had still looked like `CPU      17%` because their fixed `100%`/`100°C` slots right-aligned shorter values. GPU Power also right-aligned values in a shape-sized slot. The scalar tab is now leading-aligned after a nominal 3 pt label gap, with the remainder of a fixed numeric slot on the value's *right*. Scalar slot widths are CPU/GPU 37 pt, temperature 40 pt, and GPU Power 79 pt, including its scientific fallback. The existing outer widths in the table above are unchanged. Measured English label→value gaps were CPU 3.08 pt, GPU 3.68 pt, Temp 3.66 pt, and GPU Power 3.79 pt; Simplified Chinese measured CPU 3.08 pt, GPU 3.68 pt, 温度 3.20 pt, and GPU 功耗 3.30 pt. The gap and value start stayed fixed across each scalar metric's tested values, including unavailable and power fallback; no text clipped. Real AppKit captures show `CPU 17%`, `GPU 16%`, `Temp 61°C`/`温度 61°C`, and GPU Power in both languages visibly tighter than the preceding contact sheet. The Network branch, formatter, RX/TX slots, 249 pt outer width, and measured component gaps are unchanged; the before/after JSON values match exactly. This UI-only follow-up added no timer, polling, observer, collector, SQLite work, or cadence change.

**Network presentation order.** The menu bar now shows Upload / TX / `↑` first and Download / RX / `↓` second; the popover shows Upload above Download in English and 上传 above 下载 in Chinese. The menu examples `NET ↑ 0 B/s ↓ 0 B/s`, `NET ↑ 727.6 KB/s ↓ 52.8 MB/s`, and `NET ↑ 1.0 GB/s ↓ 999.9 MB/s` passed formatter and real AppKit status-button checks. The bilingual popover smoke injected distinct TX and RX values and verified their labels, values, and row order. All 88 real status-bar cases passed fixed width, neighbor stability, and clipping checks; Network remained 249 pt and scalar metric widths and gaps matched the preceding evidence. The UI-order commit was a presentation-order change only. It changed no telemetry or database semantics: `ifi_obytes` still feeds TX/Upload and `network_tx_bytes_per_sec`; `ifi_ibytes` still feeds RX/Download and `network_rx_bytes_per_sec`. Network slot widths, spacing, formatter, sampler, cadence, SQLite schema, and scalar menu layouts were not changed by the UI commit. AF separately records the later counter-source correctness fix.

## AF. Real network direction validation

**Configuration and interface.** On macOS 27.0, local `networkQuality -h` confirms `-u` disables upload, `-d` disables download, `-M` caps runtime, `-I` binds an interface, and `-c` emits machine-readable output. The IPv4 default route and the ordinary sampler both selected `en0`; the saved native inventory lists `en0` as the only selected interface. Loopback, `awdl0`, `llw0`, bridge, inactive `en` devices, and `utun0`–`utun9` were excluded. The first two bounded `networkQuality -I en0 -u` attempts returned `NetworkQualityErrorDomain` 1003 with no throughput. An unbound diagnostic succeeded and reported `interface_name=en0`. The final commands were `/usr/bin/networkQuality -u -M 10 -c` and `/usr/bin/networkQuality -d -M 10 -c`; both reported `interface_name=en0`, matching the route and selected interface. No trusted user-controlled transfer endpoint was needed. There were seven bounded invocations total: two failed bound attempts, one successful unbound diagnostic download, one pre-fix download/upload pair, and one post-fix download/upload pair. The five completed transfers reported approximately 1.62 GB in aggregate; the short repeat was required to verify the discovered counter bug fix.

**Counter correction.** During the initially contaminated baseline (an unrelated user download that ended before the controlled baseline), `NET_RT_IFLIST2` byte fields decreased at a 4 GiB boundary. A direct comparison then found route-message RX near 3.14 GB while `IFMIB_IFDATA` and `netstat` reported over 50.38 GB for the same `en0`. The old accumulator correctly avoided a huge false positive but classified the wrapped interval as a reset, losing one measurement. The sampler now keeps the same route-based interface filtering, then reads full `if_data64` bytes from `IFMIB_IFDATA` for each selected interface. Name/index and current eligibility are checked before accepting a counter. A synthetic 4 GiB crossing test passed without reset or spike; the ordinary App's post-fix real-transfer rows were all measured, nonnegative, and within normal magnitude. The counter source metadata was updated to `IFMIB_IFDATA`; SQLite column names, units, quality meaning, and RX/TX direction were unchanged.

**Post-fix measurement.** The ordinary App stayed running during a fresh 60.02-second baseline and both controlled transfers. Values below use decimal MB (1,000,000 bytes); reference throughput is converted from bits/s to MB/s. Native averages divide the total 64-bit counter delta by the observed monotonic phase duration. App averages use the committed v4 SQLite rows whose timestamps fall inside that phase, so their windows only approximately align with `networkQuality`.

| Phase | Duration | Apple reference | en0 cumulative RX / TX | Native RX / TX average | App SQLite RX / TX average | App rows |
|---|---:|---:|---:|---:|---:|---:|
| Baseline | 60.02 s | — | 6.52 / 0.84 MB | 0.11 / 0.01 MB/s | 0.11 / 0.01 MB/s | 29 |
| Download only | 6.14 s | 66.89 MB/s down, 371.75 MB transferred | 396.61 / 1.73 MB | 64.58 / 0.28 MB/s | 56.55 / 0.24 MB/s | 3 |
| Cooldown | 30.03 s | — | 0.34 / 0.41 MB | 0.01 / 0.01 MB/s | 0.01 / 0.01 MB/s | 15 |
| Upload only | 10.28 s | 7.45 MB/s up, 54.66 MB transferred | 2.57 / 53.38 MB | 0.25 / 5.19 MB/s | 0.22 / 4.49 MB/s | 5 |
| Recovery | 30.02 s | — | 0.21 / 0.25 MB | 0.01 / 0.01 MB/s | 0.01 / 0.01 MB/s | 14 |

The full ordinary-App run had a 2.106-second median fast-sample interval. The first SQLite response inside each transfer started about 1.25 seconds after download launch and 0.51 seconds after upload launch; both directions returned to near-baseline in the next recovery phase. Download App peaks were 71.44 MB/s RX and 0.38 MB/s TX; upload peaks were 5.89 MB/s TX and 0.28 MB/s RX. Across the five phases, selected interface name/index/link marker stayed stable, native counters increased monotonically, and every included SQLite RX/TX row had `measured` quality, a non-NULL nonnegative value, and an actual window of 2.10–2.16 seconds. SQLite `user_version=4` and `quick_check=ok`. No negative rate, false huge spike, repeated baseline reset, or stale window was observed. The distinct reference and App averages are plausible given different timing windows and interface/protocol overhead.

**Mapping, filtering, and cost.** Full `ifi_ibytes` remains RX → Download → `↓` → `network_rx_bytes_per_sec`; full `ifi_obytes` remains TX → Upload → `↑` → `network_tx_bytes_per_sec`. The menu puts TX first; the popover puts Upload first; SQLite preserves independent RX/TX columns. `utun` interfaces were present and excluded, but VPN double-counting was not runtime-tested with a controlled VPN transfer. Multi-interface aggregation was not runtime-tested because only one eligible physical link was available; both retain their prior synthetic checks. The fixed sampler uses no new timer or polling. A post-fix 100-read native benchmark averaged 0.839 ms (median 0.695, p95 2.041) versus the earlier 1.083 ms (median 0.781, p95 2.969); these short measurements have ambient variation. The post-fix ordinary run retained the 2.106-second median cadence. Process/socket inspection found one ordinary App PID, no child or active network socket, and source inspection found no `networkQuality`, curl, URLSession, ping, Speedtest, test server, or active HTTP path in the App. `networkQuality` exists only in test tooling. The backend fix changed no status-bar layout, formatter, SQLite schema, or telemetry cadence; bilingual AppKit smoke and backend/metric checks passed afterward.

## Evidence

- `docs/results/minimal-v01-pre-network-regression.jsonl` and its summary: 900-second v3 ordinary-build observation.
- `docs/results/network-ab.json`: ordinary-build A/B CPU/RSS, quality, and cadence.
- `docs/results/network-ab-summary.json` and `docs/results/network-sampler-benchmark.json`: concise comparison, durable-growth projection, and native sampler timing.
- `docs/results/network-latency-disabled.json` and `docs/results/network-latency-enabled.json`: supplemental 60-tick collector timing in each phase.
- `docs/results/migration-checks.json`: copy migrations and malformed/future-schema rejection.
- `docs/results/real-db-v4-check.json`: read-only integrity and row-preservation comparison against both real backups.
- `docs/results/status-width.json`: 88-case real AppKit status-item width, neighboring-item stability, component gaps, and slot-width check.
- `docs/results/status-visual.png`: inspected English/Chinese contact sheet from real AppKit status-button bitmap captures for every requested visual example.
- `docs/results/network-process-observations.jsonl` and `docs/results/network-db-size.jsonl`: external process and database snapshots.
- `docs/results/network-direction-interfaces.json`, `network-direction-{baseline,download,cooldown,upload,recovery}.json`, and `network-direction-summary.json`: actual selected/excluded interfaces, native full-64-bit counters, reference throughput, and read-only ordinary-App SQLite comparison.
- `tests/run-history-checks.py`, `tests/run-migration-checks.py`, `tests/run-network-checks.sh`, `tests/run-localization-checks.sh`, `app/ui-smoke.sh`, and `tests/run-popover-layout.sh`: focused repeatable checks.

## Decision

The minimal monitor and migration checks pass. Controlled download and upload now show the expected dominant RX and TX directions in the native counters and ordinary-App SQLite, with rates reasonably consistent with Apple's reference. The discovered 4 GiB counter truncation was corrected with full 64-bit `IFMIB_IFDATA` counters and revalidated. The requested Network acceptance gate is met on this machine. This is a readiness decision for the next polish stage, not a claim that VPN and multiple-physical-interface runtime tests were performed.

READY FOR MINIMAL V0.1 POLISH

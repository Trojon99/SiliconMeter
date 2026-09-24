# Minimal v0.1 polish report

This is the local **0.1.0 (1)** release-candidate polish record, not a public release. The feature scope remains Monitor + Menu Bar + Local History. The original Step 2 and Step 2.6 experiment provenance was not changed.

**Preflight.** The checkout was clean on `phase3/minimal-monitor-v0.1` at `99a2999`, including the committed full-64-bit Network counter fix. The ordinary app was running from `app/ComputeMonitor.app`; its v4 SQLite database passed `quick_check=ok` with existing rows intact. The final observation uses ordinary App PID 4097 and binary SHA-256 `4e67b687c59aac5be4653ffaab64350f5a89a86c778967a5bc56d68e6998199c`. No Step 2/2.6 source or evidence file changed.

## A. UI final state

The five fixed-width menu modes remain CPU, GPU, Temp, GPU Power, and `NET ↑ Upload ↓ Download`. No status-item formatter, width, numeric-slot, or telemetry-cadence code changed in this polish. The 88-case real AppKit status-bar fixture passed with the same outer widths and neighbor stability as the accepted result. One initial run observed a transient offscreen menu-bar reflow while macOS repositioned test items; a single repeat passed all 88 cases. The 740-point single popover now presents CPU, GPU, Memory, Thermal, Network, primary-metric controls, History, Language, Launch at Login, Open Data Folder, and Quit. Upload remains above Download. English and Chinese AppKit layout checks found no control outside the popover bounds.

## B. Localization

All new user-visible login-item labels and status messages use the existing `Localizer` resources. A static check found all 44 literal `tr`/popover-line keys in both language resources. English and Simplified Chinese UI smoke passed metric switching, Network order, History controls, layout bounds, language switching, and unchanged live telemetry. The three-process language persistence check passed. Standard metric symbols and units remain language-neutral.

## C. Launch at Login

The popover checkbox uses Apple's [Service Management `SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) on macOS 13+. Opening the popover reads the operating-system status, and changing the checkbox calls `register()` or `unregister()`. A pending approval state remains visibly checked with an approval message; `notFound` is displayed as unavailable and disabled. Error messages are localized. There is no LaunchAgent plist, daemon, root requirement, preference shadow state, or telemetry timer. AppKit smoke verified English/Chinese status presentation and on/off callbacks without mutating the user's login items. The local development app and smoke bundle have only ad-hoc linker signatures without a Team ID or sealed bundle resources; the smoke bundle's native status was `notFound`, and strict `codesign --verify` rejected the app bundle because resources were not sealed. Actual system registration, approval, unregister, and restart behavior therefore remain a **signed-build release check**, not a claimed local pass.

## D. Primary metric persistence

The existing `UserDefaults` preference was centralized without changing its key or values. Separate processes in an isolated preference domain wrote and restored CPU, GPU, Temp, GPU Power, and NET; invalid stored values fall back to CPU. The preference remains outside SQLite. AppKit smoke separately exercised all five mode buttons without changing collector count.

## E. History UX

The lightweight History area still shows Recording and Database Size and opens `HistoryLogger.defaultURL.deletingLastPathComponent()`, the Application Support folder containing the one real `telemetry.sqlite3`. The app does not create a second database, chart, or SQL viewer. SQLite v4 integrity, row appending, and the live data path are part of the final observation below.

## F. Privacy

Both READMEs now state that telemetry remains local, with no analytics, cloud upload, user-file-content collection, or per-process attribution. Network monitoring reads system counters but generates no monitoring traffic. Source inspection found no active network request path in the app; the final process observation checks children and sockets at phase boundaries.

## G. Compatibility limitations

The tested host is an Apple M1 Max on macOS 27.0 build 26A428. IOReport and AppleSMC depend on undocumented/private behavior that may change with other Macs or macOS versions. Other Apple Silicon support is best effort. VPN transfer and multi-physical-interface aggregation were not runtime-tested in the preceding Network acceptance; their synthetic filtering checks remain recorded in `MINIMAL_V01_REPORT.md`.

## H. README status

`README.md` and `README.zh-CN.md` retain parallel structure and describe the same 0.1.0 candidate, features, metrics, History growth, privacy, installation/build, data path, tested hardware, limits, and license status. Both point users to **Open Data Folder** and distinguish the local unsigned build from a signed release. `docs/RELEASE_CHECKLIST.md` prepares later release work without creating a tag, push, package, or GitHub Release.

## I. Version and app identity

The existing product name is **Compute Monitor**. Bundle metadata is `CFBundleIdentifier=local.compute-monitor`, `CFBundleShortVersionString=0.1.0`, `CFBundleVersion=1`, and `LSUIElement=true`; the app uses accessory activation and has no Dock icon in the UI smoke. The distributed bundle identifier needs an explicit release decision. No brand name was invented.

## J. Final 30-minute stability test

The final ordinary App binary ran under PID 4097 for **1,799.88 seconds** of external observation with 121 process/SQLite snapshots: 10 minutes normal background, 10 minutes with one external local SHA-256 CPU process, and 10 minutes recovery. The workload was a child of the test runner, not the App; it stopped at the recovery boundary. No Network speed test or user-file input was used. The App PID and SQLite run ID remained unchanged. At start, 10 minutes, 20 minutes, and 30 minutes, the App had **0 children and 0 active network sockets**. A graceful Quit set that run's `end_utc_ms`; the real database remained at schema v4 with `integrity_check=ok`. The full trace and summary are `docs/results/v01-polish-stability.jsonl` and `v01-polish-stability-summary.json`.

## K. CPU, RSS, and collection results

The ordinary App used **12.805 seconds of CPU time**, or **0.711% of one core** over the 30 minutes. Per-phase one-core CPU averages were 0.882% idle, 0.593% during external local compute, and 0.663% during recovery. Sampled RSS averaged 78.15 MiB and peaked at 81.72 MiB. RSS stepped upward during the first phase and then stayed about 81.3–81.7 MiB through the last 20 minutes; the source of that step was not established. The ordinary app's fast-sample cadence median was **2.105 seconds**, maximum **2.161 seconds**, with 855 fast rows, 285 slow rows, and 57 writer batches added. Across all fast and slow quality fields in this run, invalid and stale counts were **0**; two unavailable entries in each table were observed, consistent with startup baselines. The same prior production Network-enabled baseline measured 0.368% of one core and 53.31 MiB final RSS in a closed-popover 15-minute run before the 64-bit counter correction; the full runs had different UI/ambient conditions, so this comparison alone does not isolate a regression. The separate review-only 60-tick collector fixture measured **4.713 ms mean, 4.214 ms median, 11.020 ms p95, and 15.875 ms maximum**, against its earlier Network-enabled mean of 4.63 ms. This fixture excludes AppKit and SQLite work and is not a per-tick timing claim for the ordinary binary. A reliable runtime timer count is unavailable; source still has one fast `DispatchSourceTimer`, with no new login-setting timer or observer.

To narrow the memory comparison, a freshly launched pre-polish App built from `99a2999` and the current App were each observed for 90 seconds on the same host with the popover closed, using the same external `libproc` observer and 30-second CPU warmup. A process check confirmed that only the measured App was running in each valid observation. The old App averaged **0.670%** of one core after warmup and ended at **59.94 MiB RSS**; the current App averaged **0.624%** and ended at **67.84 MiB RSS**. The current App therefore used **0.046 percentage points less** CPU and **7.91 MiB more** resident memory in this short comparison. Both RSS traces were nearly flat over 90 seconds (old 59.67–59.94 MiB; current 67.52–67.84 MiB). The absolute CPU cost remains below 1% of one core, with no sustained memory rise in the 30-minute run. This is a measurable, bounded memory increase, not proof of zero regression; its exact cause was not isolated. Evidence: `v01-polish-matched-old.json`, `v01-polish-matched-new.json`, and `v01-polish-fresh-closed.json` in `docs/results/`.

## L. Database growth

The final 30-minute run increased SQLite logical database size (`PRAGMA page_count × page_size`) by **344,064 bytes**, equivalent to **0.688 MB/hour** if sustained. Its linear projection is **0.688 MB in 1 hour, 16.52 MB in 24 hours, 115.61 MB in 7 days, and 495.45 MB in 30 days**. This is close to the previous 15-minute durable-main-file estimate of 0.698 MB/hour; the two methods are not identical. Both are short-window estimates, exclude transient WAL/SHM file size, and do not promise a fixed future rate. `PRAGMA quick_check=ok` after the final run. v0.1 remains append-only, with no retention, downsampling, or automatic deletion.

## M. Unresolved release blockers

- Signed distribution-build validation of Launch at Login status, registration, approval, disable, and restart.
- A LICENSE decision before any public GitHub release; no license is present.
- Confirming whether `local.compute-monitor` is the desired distributed bundle identifier.
- Later release work: signing, notarization, DMG/ZIP, checksum, bilingual release notes, and tag. None was performed during polish.

## N. Files changed

The UI commit changed `app/ComputeMonitor.swift`, both `Localizable.strings` files, and two isolated preference-check files. The documentation commit covers both READMEs, `PRODUCT_SCOPE.md`, `tests/README.md`, the release checklist, this report, and test-only stability evidence. No Step 2/2.6 provenance, telemetry metric, status-bar layout, or SQLite schema file changed.

## O. Commits

The preceding Network acceptance remains in `f173dad` and `99a2999`; these commits were not squashed. UI polish is `1a06874` (`ui: polish minimal v0.1 controls`). This report, bilingual documentation, release checklist, and verification evidence are included in the subsequent documentation commit.

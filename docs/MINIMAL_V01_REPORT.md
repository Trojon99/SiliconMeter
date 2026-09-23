# Minimal Monitor v0.1 verification report

This report records the scope recovery, bilingual UI, Network candidate, and local validation. The product remains a generic Apple Silicon menu-bar monitor and SQLite recorder. All times in evidence files are UTC.

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

**J. Menu bar.** One variable-width primary metric is selected from CPU, GPU, temperature, GPU power, and Network. Invalid or unavailable values show `—`; no recording or workload badge is added.

**K. Popover.** Current CPU, GPU, Network, memory, and thermal readings appear with compact History status, database size, Open Data Folder, language choice, and Quit. There is no chart or analysis UI.

**L. History.** One background serial SQLite writer retains the Step 3.2 batch/WAL/UTC/quality behavior and graceful flush. Local SQLite readers can query committed rows. Network uses the same fast sample rows and time axis.

**M. Growth.** Step 3.2 measured 0.572 MB/hour before Network. During the v4 enabled run, the database main file grew 172,032 bytes in 887.1 seconds between read-only size snapshots after A's checkpoint and after B's graceful exit: approximately **0.698 MB/hour**, or 16.75 MB/day, 117.26 MB/7 days, and 502.56 MB/30 days at the same rate. This is a short-window linear projection, not a retention guarantee. Active WAL/SHM size is separate from durable growth.

**N–O. Stability and resources.** The ordinary v3 app ran 900.3 seconds with one PID, 420 additional fast rows, 140 additional slow rows, 28 writer batches, and integrity `ok` at every 30-second check. External `ps` observations gave 0.303% mean CPU of one core; late RSS varied by 0.05 MiB around 93.7 MiB. It had no child process or network socket. The final v4 enabled app then ran 900.01 seconds with 428 fast rows, 143 slow rows, 29 writer batches, a 2.101-second median cadence, 0.368% CPU of one core after warmup, 53.31 MiB final RSS, and 0.22 MiB late RSS range. The different v3 RSS includes an opened popover; the A/B comparison below uses matched closed-popover conditions. v4 integrity was `ok` after graceful exit. UI smoke separately switched all five menu choices and checked live data, width, and popover containment.

**P–Q. Changes and commits.** The product branch contains the UI/localization, v4 migration/history, native Network sampler, tests, and bilingual documentation in `0a2f4f2` (`feat: build bilingual minimal monitor with network telemetry candidate`). The archive commit `7adb5ed` is separate and is not an ancestor of the product branch. This report is committed separately.

**R. Remaining limits.** IOReport/AppleSMC compatibility remains hardware and macOS dependent. Network physical-link filtering is conservative. Controlled download, upload, hardware interface transition, and VPN transfer were unavailable in this environment, so the Network acceptance gate cannot be fully closed yet. The Network code is a tested candidate on the development branch, not a validated release decision.

## S–W. English and Simplified Chinese

**S–T.** `app/Localization.swift` loads `en.lproj` and `zh-Hans.lproj` resources through one localizer. First launch follows the system language for Simplified Chinese and uses English otherwise. A manual choice applies immediately and is saved in `UserDefaults`, outside the telemetry database. Cross-process restart persistence passed in the normal user session.

**U–V.** English and Chinese AppKit smoke tests passed for menu labels, Network/History/popover text, estimated/invalid meanings, live telemetry preservation, and control bounds. Long boundary titles use the variable-width status item. A separate offscreen layout test passed both languages in the 740-point popover.

**W.** `README.md` and `README.zh-CN.md` link to each other and cover features, metrics, history, privacy, requirements, installation, source build, data location, limits, private API risk, and license with matching structure.

## X–AD. Network RX/TX candidate

**X. Backend.** `NetworkSampler` reads `NET_RT_IFLIST2` / `if_msghdr2.ifm_data` 64-bit byte counters with native `sysctl`, then divides per-interface deltas by the actual monotonic interval. It runs inside the existing approximately 2-second fast collector tick, without another timer, subprocess, packet capture, or network request. [Darwin sysctl](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/sysctl.3.html) and [Apple's interface-message definition](https://developer.apple.com/documentation/kernel/if_msghdr2) describe the underlying APIs.

**Y. Filtering.** Eligible interfaces must be up/running, Ethernet-type, and report a positive link rate. The sampler excludes loopback, tunnel, AWDL/LLW, bridge, and known virtual/peer names. It sums separate physical-link deltas and never adds `utun` on top of a lower link. This can omit unusual physical adapters and cannot classify every possible virtual adapter perfectly.

**Z. Correctness.** Native synthetic checks passed baseline, independent RX/TX direction, two-interface sum, measured zero, disappearance/reappearance, counter reset, index/link change, and stale-window cases. The host had one eligible physical interface in the live two-read check. The 15-minute ordinary run recorded five valid zero/zero windows, supporting idle-zero semantics. Ambient traffic was observed; no controlled external download/upload was performed because no trusted endpoint was available. Thus real-transfer direction remains unverified.

**AA. Overhead.** The **same ordinary binary** ran 600.01 seconds with Network disabled and 900.01 seconds enabled, with a 60-second warmup excluded from CPU averages. External libproc measured 0.331% versus 0.368% of one core, an increase of 0.037 percentage points; final RSS was 53.19 versus 53.31 MiB, an increase of 0.12 MiB. Late RSS ranges were 0.19 versus 0.22 MiB. Median fast cadence was 2.100 versus 2.101 seconds; invalid/stale Network counts were zero. The enabled phase had 427 measured rows and one initial unavailable baseline row, including five valid zero/zero windows. A separate 100-read native sampler timing check averaged 1.083 ms (median 0.781 ms, p95 2.969 ms); this is a local system-call timing result, not a power measurement. Network adds no timer, and process snapshots during A and at B start/late B showed no child or network socket. A review-only collector check ran 60 ticks per phase with the same sampling code: mean 3.94 ms disabled and 4.63 ms enabled (0.69 ms difference), median 3.65 and 4.19 ms. This excludes AppKit and SQLite; ordinary-build collector latency cannot be isolated externally. Wakeups and Energy Impact are unavailable. Context switches are recorded but are not wakeups. These sequential A/B runs are subject to ambient-system variation.

**AB. History.** `fast_samples` stores `network_rx_bytes_per_sec` and `network_tx_bytes_per_sec` as bytes/s, each with quality and actual window. No eligible interface or fresh baseline means `unavailable` and NULL; measured zero is numeric zero. Old rows keep NULL/unavailable. `docs/HISTORY_SCHEMA.md` has units and read-only SQL examples.

**AC. UI.** English shows Network, Download, Upload; Chinese shows 网络, 下载, 上传. Both menu-bar modes use compact `NET ↓… ↑…`, retaining separate units when RX/TX scales differ. Both languages passed live AppKit and layout smoke checks.

**AD. VPN and multiple interfaces.** Multiple independent eligible interfaces are summed in synthetic tests; no second physical link was available for a live transition. An active `utun` was present on the host but excluded by the filter; no controlled VPN transfer was available to measure double counting empirically.

## Evidence

- `docs/results/minimal-v01-pre-network-regression.jsonl` and its summary: 900-second v3 ordinary-build observation.
- `docs/results/network-ab.json`: ordinary-build A/B CPU/RSS, quality, and cadence.
- `docs/results/network-ab-summary.json` and `docs/results/network-sampler-benchmark.json`: concise comparison, durable-growth projection, and native sampler timing.
- `docs/results/network-latency-disabled.json` and `docs/results/network-latency-enabled.json`: supplemental 60-tick collector timing in each phase.
- `docs/results/migration-checks.json`: copy migrations and malformed/future-schema rejection.
- `docs/results/real-db-v4-check.json`: read-only integrity and row-preservation comparison against both real backups.
- `docs/results/network-process-observations.jsonl` and `docs/results/network-db-size.jsonl`: external process and database snapshots.
- `tests/run-history-checks.py`, `tests/run-migration-checks.py`, `tests/run-network-checks.sh`, `tests/run-localization-checks.sh`, `app/ui-smoke.sh`, and `tests/run-popover-layout.sh`: focused repeatable checks.

## Decision

The minimal monitor and migration checks pass, and the measured Network overhead is small on this machine. The required controlled real-transfer direction check is still missing because no trusted download/upload endpoint was available. The Network candidate remains on the development branch for that acceptance check; v0.1 is not ready for polish or release under the requested gate.

NOT READY FOR MINIMAL V0.1 POLISH

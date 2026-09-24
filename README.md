English | [简体中文](README.zh-CN.md)

# SiliconMeter

A lightweight Apple Silicon telemetry monitor and local history recorder for the macOS menu bar. Version **0.1.0** is a local release candidate; no public build has been released.

## UI preview

Screenshots will be added with a future release. The status item shows one selected metric, such as `CPU 23%`, `GPU 91%`, `Temp 61°C`, `GPU Power 14.0W`, or `NET ↑ 1.3 MB/s ↓ 12.4 MB/s`.

## Features

- Live status item with five selectable metrics and a compact popover for current system telemetry.
- A fixed menu-bar item width for each metric and language, so changing readings do not move neighboring status items.
- Local SQLite history recorded continuously from the same shared snapshots, with a serial batched writer and WAL.
- English and Simplified Chinese UI, with immediate switching and a locally saved language choice.
- A locally saved primary-metric choice and an optional native **Launch at Login** control.
- Ordinary-user operation without a helper, persistent child process, `powermetrics`, outgoing network connections, or telemetry upload.

## Supported metrics

CPU total and validated P-core/E-core activity; GPU active residency, estimated weighted active frequency, and estimated GPU power; Network download/upload rate; Tp05/Tg05 temperatures; VM and unified-memory fields, swap, memory pressure, and thermal state. Network is the current aggregate receive/transmit rate across selected external network interfaces. It reads native cumulative counters and sends no test traffic. VPN tunnel counters are excluded to avoid counting traffic again on top of the underlying link. An unavailable or invalid status-item value displays `—`, never a made-up zero. Estimated values are labeled in the popover and in history quality columns.

## History logging

The app records fast samples about every 2 seconds and slow samples about every 6 seconds. Network RX/TX share the fast timestamp, quality, and actual measurement-window fields. It batches writes about every 30 seconds and flushes on normal Quit. A crash can lose only the latest uncommitted batch. The popover shows recording status, database size, and an **Open Data Folder** button. Ordinary SQLite tools can read committed history; see [schema v4, units, and read-only queries](docs/HISTORY_SCHEMA.md). History database grows over time. The final 30-minute candidate increased SQLite logical size by 344,064 bytes, about 0.688 MB/hour. At that short-run rate, the projection is 0.688 MB in 1 hour, 16.52 MB in 24 hours, 115.61 MB in 7 days, and 495.45 MB in 30 days. A prior durable-file estimate was 0.698 MB/hour. These are estimates, not storage limits; active WAL and SHM files add temporary disk use. Use **Open Data Folder** to find the SQLite file. v0.1 does not delete, retain by age, or downsample history; retention is for a later version.

## Privacy

All telemetry and history stay on this Mac. Network monitoring reads system interface counters and does not generate monitoring traffic or run a speed test. The app has no analytics, cloud service, telemetry upload, or per-process attribution, and it does not collect user file contents. The database stores system metrics and app-run metadata, without workload labels. Language and primary-metric choices are local `UserDefaults` preferences, outside the telemetry database.

## System requirements

Apple Silicon Mac with macOS 13 or newer, outside App Sandbox. **Tested on: Apple M1 Max, macOS 27.0 (build 26A428).** Other Apple Silicon chips and macOS releases are best effort; compatibility is not guaranteed. No root privilege is required.

## Installation

There is no signed or notarized downloadable release yet. The build below is for local development. A future public release should include short **English** and **简体中文** sections in its release notes.

## Build from source

Install Apple Command Line Tools with Swift and Clang, then run:

```sh
sh app/build.sh
open app/SiliconMeter.app
```

Click the status item to view current telemetry, choose a primary metric or language, enable **Launch at Login**, open the data folder, or Quit. The app runs as an accessory without a Dock icon. Launch at Login uses macOS Service Management; the local ad-hoc signed development bundle may show it as unavailable, while a properly signed release build must be verified separately. Focused checks are documented in [tests/README.md](tests/README.md). [Product scope](docs/PRODUCT_SCOPE.md) defines the v0.1 boundary.

## Data location

The database is `~/Library/Application Support/SiliconMeter/telemetry.sqlite3`. Its `-wal` and `-shm` sidecars may exist while the app runs. Use SQLite's backup API for a consistent live backup. Read-only external programs can query the database directly; the app does not provide an HTTP or socket API.

## Upgrade notes

Early local development builds used a `Compute Monitor` data folder. Quit the older app before opening SiliconMeter. On first launch, SiliconMeter moves that folder to its new location if the new folder does not exist. If both folders exist, it keeps both untouched and uses the SiliconMeter folder; check the local log before resolving that conflict manually.

## Known limitations

Private IOReport and AppleSMC behavior can change with macOS or hardware updates; unavailable capabilities remain visibly unavailable. GPU power and weighted frequency are estimates, not externally calibrated measurements. Network selection is conservative: unusual physical links without Ethernet type or a reported link rate may be omitted; VPN tunnel traffic is not separately counted. There is no in-app chart, data retention policy, process attribution, workload analysis, or automatic tuning. Workloads such as local LLMs, compilation, and rendering are external use cases for the generic history. A preexisting v2 database may retain an unused legacy experimental table to preserve its data; fresh and v1-upgraded v4 databases do not create it.

## Private API compatibility risk

The full telemetry build is intentionally non-App-Sandboxed because the tested sandbox blocked IOReport and AppleSMC access. These private interfaces may break or disappear in future macOS versions. The current local build is not Developer ID signed or notarized for distribution.

## License

MIT License. See [LICENSE](LICENSE).

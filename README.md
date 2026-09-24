English | [简体中文](README.zh-CN.md)

# Compute Monitor

A lightweight Apple Silicon telemetry monitor and local history recorder for the macOS menu bar.

## UI preview

Screenshots will be added with a future release. The status item shows one selected metric, such as `CPU 23%`, `GPU 91%`, `Temp 61°C`, `GPU Power 14.0W`, or `NET ↓12.4 MB/s ↑1.3 MB/s`.

## Features

- Live status item with five selectable metrics and a compact popover for current system telemetry.
- A fixed menu-bar item width for each metric and language, so changing readings do not move neighboring status items.
- Local SQLite history recorded continuously from the same shared snapshots, with a serial batched writer and WAL.
- English and Simplified Chinese UI, with immediate switching and a locally saved language choice.
- Ordinary-user operation without a helper, persistent child process, `powermetrics`, outgoing network connections, or telemetry upload.

## Supported metrics

CPU total and validated P-core/E-core activity; GPU active residency, estimated weighted active frequency, and estimated GPU power; Network download/upload rate; Tp05/Tg05 temperatures; VM and unified-memory fields, swap, memory pressure, and thermal state. Network is the current aggregate receive/transmit rate across selected external network interfaces. It reads native cumulative counters and sends no test traffic. VPN tunnel counters are excluded to avoid counting traffic again on top of the underlying link. An unavailable or invalid status-item value displays `—`, never a made-up zero. Estimated values are labeled in the popover and in history quality columns.

## History logging

The app records fast samples about every 2 seconds and slow samples about every 6 seconds. Network RX/TX share the fast timestamp, quality, and actual measurement-window fields. It batches writes about every 30 seconds and flushes on normal Quit. A crash can lose only the latest uncommitted batch. The popover shows recording status, database size, and an **Open Data Folder** button. Ordinary SQLite tools can read committed history; see [schema v4, units, and read-only queries](docs/HISTORY_SCHEMA.md). No retention or aggregation is implemented. A 15-minute v4 run observed about 0.698 MB/hour of durable growth, a short-run estimate; see the [verification report](docs/MINIMAL_V01_REPORT.md). Active WAL and SHM files add temporary disk use.

## Privacy

Collection and history stay on this Mac. The app reads Network counters but does not make a network connection or run a speed test. There is no account, network service, cloud sync, analytics, or upload. The database stores system metrics and app-run metadata, without process attribution or workload labels. Language and primary-metric choices are local `UserDefaults` preferences, outside the telemetry database.

## System requirements

Apple Silicon Mac with macOS 13 or newer, outside App Sandbox. The current hardware and long-run evidence is for M1 Max on the documented macOS 27.0 setup; other chips and releases are not yet validated. No root privilege is required.

## Installation

There is no signed or notarized downloadable release yet. The build below is for local development. A future public release should include short **English** and **简体中文** sections in its release notes.

## Build from source

Install Apple Command Line Tools with Swift and Clang, then run:

```sh
sh app/build.sh
open app/ComputeMonitor.app
```

Click the status item to view current telemetry, choose a primary metric or language, open the data folder, or Quit. The app runs as an accessory without a Dock icon. Focused checks are documented in [tests/README.md](tests/README.md). [Product scope](docs/PRODUCT_SCOPE.md) defines the v0.1 boundary.

## Data location

The database is `~/Library/Application Support/Compute Monitor/telemetry.sqlite3`. Its `-wal` and `-shm` sidecars may exist while the app runs. Use SQLite's backup API for a consistent live backup. Read-only external programs can query the database directly; the app does not provide an HTTP or socket API.

## Known limitations

Private IOReport and AppleSMC behavior can change with macOS or hardware updates; unavailable capabilities remain visibly unavailable. GPU power and weighted frequency are estimates, not externally calibrated measurements. Network selection is conservative: unusual physical links without Ethernet type or a reported link rate may be omitted; VPN tunnel traffic is not separately counted. There is no in-app chart, data retention policy, process attribution, workload analysis, or automatic tuning. Workloads such as local LLMs, compilation, and rendering are external use cases for the generic history. A preexisting v2 database may retain an unused legacy experimental table to preserve its data; fresh and v1-upgraded v4 databases do not create it.

## Private API compatibility risk

The full telemetry build is intentionally non-App-Sandboxed because the tested sandbox blocked IOReport and AppleSMC access. These private interfaces may break or disappear in future macOS versions. The current local build is not Developer ID signed or notarized for distribution.

## License

No license has been selected or published yet. The repository does not currently grant an open-source license.

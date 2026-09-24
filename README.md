English | [简体中文](README.zh-CN.md)

# SiliconMeter

A lightweight Apple Silicon telemetry monitor and local history recorder for the macOS menu bar. Version **0.1.0** is available on [GitHub Releases](https://github.com/Trojon99/SiliconMeter/releases).

## UI preview

Screenshots will be added with a future release. The status item shows one selected metric, such as `CPU 23%`, `GPU 91%`, `Temp 61°C`, `GPU Power 14.0W`, or `NET ↑ 1.3 MB/s ↓ 12.4 MB/s`.

## Features

- Live status item with five selectable metrics and a compact popover for current system telemetry.
- A SiliconMeter App icon for Finder, Applications, and the DMG.
- A fixed menu-bar item width for each metric and language, so changing readings do not move neighboring status items.
- Local SQLite history recorded continuously from the same shared snapshots, with a serial batched writer, WAL, and configurable retention.
- English and Simplified Chinese UI, with immediate switching and a locally saved language choice.
- A locally saved primary-metric choice. Launch at Login is not included in unsigned v0.1.
- Ordinary-user operation without a helper, persistent child process, `powermetrics`, outgoing network connections, or telemetry upload.

## Supported metrics

CPU total and validated P-core/E-core activity; GPU active residency, estimated weighted active frequency, and estimated GPU power; Network download/upload rate; Tp05/Tg05 temperatures; VM and unified-memory fields, swap, memory pressure, and thermal state. Network is the current aggregate receive/transmit rate across selected external network interfaces. It reads native cumulative counters and sends no test traffic. VPN tunnel counters are excluded to avoid counting traffic again on top of the underlying link. An unavailable or invalid status-item value displays `—`, never a made-up zero. Estimated values are labeled in the popover and in history quality columns.

## History logging

The app records fast samples about every 2 seconds and slow samples about every 6 seconds. Network RX/TX share the fast timestamp, quality, and actual measurement-window fields. It batches writes about every 30 seconds and flushes on normal Quit. A crash can lose only the latest uncommitted batch. The popover shows recording status, database size, retention, and an **Open Data Folder** button. Ordinary SQLite tools can read committed history; see [schema v4, units, and read-only queries](docs/HISTORY_SCHEMA.md). History can grow between cleanups. Before retention, the final 30-minute candidate increased SQLite logical size by 344,064 bytes, about 0.688 MB/hour. At that short-run rate, the projection is 0.688 MB in 1 hour, 16.52 MB in 24 hours, 115.61 MB in 7 days, and 495.45 MB in 30 days. A prior durable-file estimate was 0.698 MB/hour. These are estimates, not storage limits; active WAL and SHM files add temporary disk use. Use **Open Data Folder** to find the SQLite file. v0.1 does not downsample history.

## History Retention

Choose **1 Day** (rolling 24 hours), **7 Days**, **30 Days**, or **Forever** in History. A fresh installation defaults to **30 Days**. If an existing database has no retention setting, it defaults to **Forever** so earlier history is not silently deleted. Shortening retention asks for confirmation before old rows are permanently removed; Cancel keeps the prior choice. Extending retention does not restore rows already deleted. Cleanup runs in the background and does not automatically run `VACUUM`. The displayed database size may not shrink immediately after deletion because SQLite reuses freed pages for later writes.

## Privacy

All telemetry and history stay on this Mac. Network monitoring reads system interface counters and does not generate monitoring traffic or run a speed test. The app has no analytics, cloud service, telemetry upload, or per-process attribution, and it does not collect user file contents. The database stores system metrics and app-run metadata, without workload labels. Language, primary-metric, and retention choices are local `UserDefaults` preferences, outside the telemetry database.

## System requirements

Apple Silicon Mac with macOS 13 or newer, outside App Sandbox. **Tested on: Apple M1 Max, macOS 27.0 (build 26A428).** Other Apple Silicon chips and macOS releases are best effort; compatibility is not guaranteed. No root privilege is required.

## Installation

SiliconMeter v0.1.0 is distributed as an unsigned, non-notarized open-source community build. It is not Apple verified. Source code is available for inspection and local builds. Download it from [GitHub Releases](https://github.com/Trojon99/SiliconMeter/releases) and install it as follows:

1. Download `SiliconMeter-0.1.0-arm64.dmg` from the project's GitHub Release.
2. Open the DMG and drag **SiliconMeter.app** to **Applications**.
3. Open SiliconMeter from Applications.
4. If macOS blocks the first launch, open **System Settings → Privacy & Security → Open Anyway**, then confirm **Open**. Apple describes this [manual exception process](https://support.apple.com/en-gb/102445).

This local build does not reproduce every Gatekeeper prompt that may appear after a browser download. Do not disable Gatekeeper globally.

## Build from source

Install Apple Command Line Tools with Swift and Clang, then run:

```sh
sh app/build.sh
open app/SiliconMeter.app
```

Click the status item to view current telemetry, choose a primary metric or language, open the data folder, or Quit. The app runs as an accessory without a Dock icon. Launch at Login is not included in unsigned v0.1. Focused checks are documented in [tests/README.md](tests/README.md). [Product scope](docs/PRODUCT_SCOPE.md) defines the v0.1 boundary.

## Data location

The database is `~/Library/Application Support/SiliconMeter/telemetry.sqlite3`. Its `-wal` and `-shm` sidecars may exist while the app runs. Use SQLite's backup API for a consistent live backup. Read-only external programs can query the database directly; the app does not provide an HTTP or socket API.

## Upgrade notes

Early local development builds used a `Compute Monitor` data folder. Quit the older app before opening SiliconMeter. On first launch, SiliconMeter moves that folder to its new location if the new folder does not exist. If both folders exist, it keeps both untouched and uses the SiliconMeter folder; check the local log before resolving that conflict manually.

## Known limitations

Private IOReport and AppleSMC behavior can change with macOS or hardware updates; unavailable capabilities remain visibly unavailable. GPU power and weighted frequency are estimates, not externally calibrated measurements. Network selection is conservative: unusual physical links without Ethernet type or a reported link rate may be omitted; VPN tunnel traffic is not separately counted. There is no in-app chart, process attribution, workload analysis, or automatic tuning. Workloads such as local LLMs, compilation, and rendering are external use cases for the generic history. A preexisting v2 database may retain an unused legacy experimental table to preserve its data; fresh and v1-upgraded v4 databases do not create it.

## Private API compatibility risk

The full telemetry build is intentionally non-App-Sandboxed because the tested sandbox blocked IOReport and AppleSMC access. These private interfaces may break or disappear in future macOS versions. The v0.1.0 community build has no Developer ID signature or notarization. A local ad-hoc code seal is only a build detail; it does not establish an Apple trusted developer identity.

## License

MIT License. See [LICENSE](LICENSE).

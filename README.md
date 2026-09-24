English | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="app/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="SiliconMeter app icon" width="128">
</p>

<h1 align="center">SiliconMeter</h1>

<p align="center"><strong>A performance memory for your Mac.</strong></p>

<p align="center">
Lightweight, local-first Apple Silicon performance monitoring for the macOS menu bar, with structured SQLite history for people, scripts, local AI models, and agents.
</p>

<p align="center">
  <a href="https://github.com/Trojon99/SiliconMeter/releases"><img alt="Release" src="https://img.shields.io/github/v/release/Trojon99/SiliconMeter?display_name=tag&sort=semver"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-333333?logo=apple">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <img alt="Local only" src="https://img.shields.io/badge/data-local--only-success">
</p>

SiliconMeter is a lightweight **Apple Silicon performance monitor**, **macOS menu bar system monitor**, and **local telemetry recorder**. It tracks CPU, GPU, temperature, estimated GPU power, network activity, memory pressure, swap, and thermal state over time, then stores the history locally in SQLite.

The goal is not only to show what your Mac is doing right now. It is to give the machine a **performance memory** that can be inspected later.

> **Think of it as a Garmin for your Mac.** Garmin records how your body performs over time; SiliconMeter records how your Mac performs over time.

That history can be queried by users, scripts, local LLMs, AI agents, or automation tools to understand resource utilization and improve external workloads such as **MLX/local LLM training and inference, llama.cpp/Ollama-style local inference, compilation, rendering, and long-running compute jobs**. SiliconMeter itself does **not** run AI, identify individual processes, or automatically tune workloads.

Version **0.1.0** is available on [GitHub Releases](https://github.com/Trojon99/SiliconMeter/releases).

## Why SiliconMeter?

Most system monitors answer one question: **what is happening now?**

SiliconMeter also keeps the timeline:

```text
Apple Silicon
     ↓
SiliconMeter
     ├── Menu bar / live telemetry
     └── Local SQLite history
                     ↓
          humans / scripts / AI agents
```

This makes it useful when you want to compare what the machine was doing before, during, and after a workload instead of relying on a single live percentage.

Typical external use cases include:

- checking whether an Apple Silicon GPU stayed active during a long local AI workload;
- comparing CPU P-core/E-core activity across different runs;
- relating GPU activity to temperature and estimated GPU power;
- spotting memory pressure, swap activity, or thermal-state changes;
- reviewing network throughput during downloads, model pulls, data ingestion, or remote work;
- feeding structured performance history into a local AI/agent for later analysis.

## Menu bar

SiliconMeter shows one selected primary metric at a time:

```text
CPU 23%
GPU 91%
Temp 61°C
GPU Power 14.0W
NET ↑ 1.3 MB/s ↓ 12.4 MB/s
```

The status item keeps a stable width for each metric/language so normal value changes do not push neighboring menu-bar items around.

<p align="center">
  <img src="docs/results/status-visual.png" alt="SiliconMeter menu-bar metric examples in English and Simplified Chinese" width="760">
</p>

## What it monitors

| Area | Telemetry |
|---|---|
| CPU | Total CPU activity plus validated P-core and E-core activity |
| GPU | Active residency and estimated active-weighted frequency |
| Power | Estimated GPU power |
| Temperature | AppleSMC Tp05 CPU sensor and Tg05 GPU sensor |
| Memory | VM/unified-memory fields, swap, memory pressure |
| Thermal | macOS thermal state and state changes |
| Network | Aggregate upload/download rate across selected external interfaces |
| History | Structured local SQLite time series with quality metadata |

Unavailable or invalid values remain explicitly unavailable rather than being converted to fake zeros. Estimated metrics are labeled as estimates in the popover/history.

## AI-ready history, without built-in AI

SiliconMeter deliberately separates **measurement** from **interpretation**.

It does not contain an LLM and does not decide whether a workload is “good” or “bad.” Instead, it records machine-readable history that another tool can query.

The live database is:

```text
~/Library/Application Support/SiliconMeter/telemetry.sqlite3
```

For example, a local script or AI agent can query recent measured GPU activity:

```sql
SELECT datetime(utc_ms/1000, 'unixepoch') AS utc,
       gpu_active*100 AS gpu_percent,
       gpu_active_window_s
FROM fast_samples
WHERE utc_ms >= (unixepoch('now') - 600)*1000
  AND gpu_active_quality = 'measured'
ORDER BY utc_ms;
```

See [the complete SQLite schema and query examples](docs/HISTORY_SCHEMA.md).

A practical workflow can be as simple as:

```text
local workload
      ↓
SiliconMeter records system telemetry
      ↓
SQLite history
      ↓
local LLM / AI agent / analysis script
      ↓
compare runs, identify unused resources, or suggest workload changes
```

SiliconMeter remains a generic monitor/logger throughout that workflow.

## Features

- Native macOS menu-bar application for Apple Silicon.
- Five selectable live status metrics: CPU, GPU, Temp, GPU Power, and NET.
- Compact popover with CPU, GPU, memory, thermal, network, and history details.
- Local SQLite recording from the same shared telemetry snapshots used by the UI.
- Fast samples about every 2 seconds and slow samples about every 6 seconds.
- Batched SQLite writer with WAL and explicit quality states.
- Configurable retention: **1 Day, 7 Days, 30 Days, or Forever**.
- English and Simplified Chinese UI with local preference persistence.
- No root helper, persistent monitoring subprocess, `powermetrics`, analytics, cloud service, or telemetry upload.
- MIT licensed and source available.

## History retention

Choose **1 Day** (rolling 24 hours), **7 Days**, **30 Days**, or **Forever**.

- Fresh installations default to **30 Days**.
- Existing databases without a retention preference default to **Forever** to avoid silently deleting earlier history.
- Shortening retention requires confirmation.
- Cleanup runs in the background and does not automatically run `VACUUM`.
- The SQLite file may not immediately shrink after deletion because freed pages are reused by later writes.

Before retention was introduced, a final 30-minute candidate grew at roughly **0.688 MB/hour** of SQLite logical size, or about **16.5 MB/day** and **495 MB/30 days** at that short-run rate. These are estimates, not storage limits; WAL/SHM files can add temporary disk usage.

## Privacy

SiliconMeter is **local-first**:

- telemetry and history stay on this Mac;
- no analytics or telemetry upload;
- no cloud service;
- no user-file-content collection;
- no per-process attribution;
- network monitoring reads system counters and generates no monitoring traffic or speed test;
- language, primary metric, and retention settings stay in local `UserDefaults`.

The database contains generic system telemetry, not workload names or prompts.

## Installation

SiliconMeter v0.1.0 is distributed as an **unsigned, non-notarized open-source community build**. It is not Apple verified.

1. Download `SiliconMeter-0.1.0-arm64.dmg` from [GitHub Releases](https://github.com/Trojon99/SiliconMeter/releases).
2. Open the DMG and drag **SiliconMeter.app** to **Applications**.
3. Open SiliconMeter from Applications.
4. If macOS blocks the first launch, open **System Settings → Privacy & Security → Open Anyway**, then confirm **Open**.

The browser-download Gatekeeper flow has been manually verified on the tested Mac. Do not disable Gatekeeper globally.

## System requirements

- Apple Silicon Mac (arm64)
- macOS 13 or newer
- No root privileges required

**Tested on:** Apple M1 Max, macOS 27.0 (build 26A428).

Other Apple Silicon chips and macOS releases are best effort. IOReport and AppleSMC are private/undocumented interfaces and may change in future macOS releases.

## Build from source

Install Apple Command Line Tools with Swift and Clang, then run:

```sh
sh app/build.sh
open app/SiliconMeter.app
```

The app runs as an accessory without a Dock icon. Launch at Login is not included in unsigned v0.1.

Focused checks are documented in [tests/README.md](tests/README.md). [Product scope](docs/PRODUCT_SCOPE.md) defines the v0.1 boundary.

## Data access

Database:

```text
~/Library/Application Support/SiliconMeter/telemetry.sqlite3
```

The app uses SQLite WAL, so `-wal` and `-shm` sidecars may exist while it is running. Use SQLite's backup API for a consistent live backup. Read-only tools can query committed history while SiliconMeter continues recording.

See [HISTORY_SCHEMA.md](docs/HISTORY_SCHEMA.md) for schema v4, units, quality states, retention semantics, and executable SQL examples.

## Upgrade notes

Early local development builds used a `Compute Monitor` data folder. On first launch, SiliconMeter migrates that folder only when the new SiliconMeter directory is absent. If both directories already exist, it leaves both untouched and uses the SiliconMeter folder.

## Known limitations

- IOReport and AppleSMC are private/undocumented interfaces and may break across hardware or macOS updates.
- GPU power and weighted GPU frequency are estimates, not externally calibrated measurements.
- Network selection is intentionally conservative; unusual physical links may be omitted.
- VPN tunnel counters are excluded to avoid double-counting the underlying link.
- There is no in-app historical chart, process attribution, workload analysis, or automatic tuning.
- The v0.1.0 community build is unsigned and not notarized.

These limitations are deliberate: SiliconMeter's role is to **measure and remember**, while interpretation stays outside the monitor.

## License

MIT License. See [LICENSE](LICENSE).

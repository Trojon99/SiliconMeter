# Minimal Monitor v0.1 product scope

SiliconMeter is a lightweight Apple Silicon macOS menu-bar telemetry monitor and local history recorder.

1. **Monitor:** One native collector publishes CPU, GPU, Network RX/TX, memory, and thermal telemetry to a shared snapshot.
2. **Menu Bar:** One selected primary metric and a small popover show current readings.
3. **Log:** One serial SQLite writer records the same snapshots as machine-readable local history.

Design principles: lightweight, local-first, low overhead, generic, machine-readable, and long-running. The ordinary-user full telemetry build runs outside App Sandbox, without root, `powermetrics`, persistent subprocesses, generated monitoring traffic, cloud services, analytics, or uploads.

Supported languages: **English** and **Simplified Chinese (zh-Hans)**. Localization belongs to the UI/product layer. It does not enter the telemetry collector or SQLite schema.

Local LLM/ML work, compilation, rendering, and other sustained workloads are possible external uses for the timestamps and metrics. The monitor does not interpret workload meaning. It has no workload-specific UI, process attribution, analysis, recommendations, model integration, automatic tuning, chart dashboard, HTTP API, or socket service.

Network means the current aggregate receive/transmit rate across selected external network interfaces. It reads native cumulative counters on the existing fast cadence, without active speed tests, subprocesses, connections, or a new timer. VPN tunnel counters are not added to the underlying physical link.

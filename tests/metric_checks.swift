// Appended to the production declarations by run-checks.sh, without the app entry point.
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !value() { fatalError(message) }
}
let uptime = ProcessInfo.processInfo.systemUptime
Localizer.shared.select(.english)
func raw(_ quality: String, _ number: Double? = nil, _ source: String = "fixture") -> NSDictionary {
    var r: [String: Any] = ["status": quality, "unit": "W", "source": source]
    if let number { r["value"] = number }
    return r as NSDictionary
}
for q in ["unavailable", "invalid", "stale", "unrecognized"] {
    let m = Metric(raw(q, 0), at: Date(), uptime: uptime)
    check(m.number == nil, "bad quality exposed a numeric zero")
    check(!m.display.contains("0"), "bad quality formatted a zero")
}
let estimated = Metric(raw("estimated", 3.2), at: Date(), uptime: uptime)
check(estimated.display == "3.2 W estimated", "estimate label lost")
check(estimated.number == 3.2, "valid estimate hidden")
let old = Metric(raw("measured", 1), at: Date(), uptime: uptime - 21)
check(old.number == nil && old.display == "Stale", "old metric remained valid")
let wallPast = Metric(raw("measured", 1), at: .distantPast, uptime: uptime)
let wallFuture = Metric(raw("measured", 1), at: .distantFuture, uptime: uptime - 21)
check(wallPast.number == 1, "wall-clock rewind affected freshness")
check(wallFuture.number == nil, "wall-clock advance affected freshness")
check(Metric(raw("measured", 1, "hw.memsize"), at: Date(), uptime: 0).number == 1, "physical memory should be static")
var snapshot = TelemetrySnapshot()
snapshot.merge(["gpuPower": raw("estimated", 3.2), "total": ["status": "measured", "value": 0.5, "unit": "ratio"]], at: Date())
check(PrimaryMetric.gpuPower.title(in: snapshot) == "GPU Power 3.2W", "power primary mismatch")
check(PrimaryMetric.cpu.title(in: snapshot) == "CPU 50%", "CPU primary mismatch")
snapshot.merge([
    "total": ["status": "measured", "value": 0.23, "unit": "ratio"],
    "gpuActive": ["status": "measured", "value": 0.91, "unit": "ratio"],
    "cpuTemperature": ["status": "measured", "value": 61, "unit": "°C"],
    "gpuPower": raw("estimated", 14)
], at: Date())
check(PrimaryMetric.cpu.title(in: snapshot) == "CPU 23%", "CPU label mismatch")
check(PrimaryMetric.gpu.title(in: snapshot) == "GPU 91%", "GPU label mismatch")
check(PrimaryMetric.temperature.title(in: snapshot) == "Temp 61°C", "temperature label mismatch")
check(PrimaryMetric.gpuPower.title(in: snapshot) == "GPU Power 14W", "GPU power label mismatch")
snapshot.merge([
    "total": ["status": "measured", "value": 1, "unit": "ratio"],
    "gpuActive": ["status": "measured", "value": 1, "unit": "ratio"],
    "cpuTemperature": ["status": "measured", "value": 100, "unit": "°C"],
    "gpuPower": raw("estimated", 99.9)
], at: Date())
check(PrimaryMetric.cpu.title(in: snapshot) == "CPU 100%", "three-digit CPU title mismatch")
check(PrimaryMetric.gpu.title(in: snapshot) == "GPU 100%", "three-digit GPU title mismatch")
check(PrimaryMetric.temperature.title(in: snapshot) == "Temp 100°C", "three-digit temperature title mismatch")
check(PrimaryMetric.gpuPower.title(in: snapshot) == "GPU Power 99.9W", "power decimal title mismatch")
snapshot.merge(["gpuPower": raw("invalid")], at: Date())
check(PrimaryMetric.gpuPower.title(in: snapshot) == "GPU Power —", "invalid became zero power")
snapshot.merge(["total": raw("measured", 1)], at: Date(), uptime: uptime - 21)
check(PrimaryMetric.cpu.title(in: snapshot) == "CPU —", "queued old reading appeared fresh")
snapshot.merge([
    "network_rx_bytes_per_sec": ["status": "measured", "value": 12_400_000.0, "unit": "B/s"],
    "network_tx_bytes_per_sec": ["status": "measured", "value": 1_300_000.0, "unit": "B/s"]
], at: Date())
check(PrimaryMetric.network.title(in: snapshot) == "NET ↓12.4 ↑1.3 MB/s", "same-unit network title")
snapshot.merge(["network_tx_bytes_per_sec": ["status": "measured", "value": 420_000.0, "unit": "B/s"]], at: Date())
check(PrimaryMetric.network.title(in: snapshot) == "NET ↓12.4 MB/s ↑420 KB/s", "mixed-unit network title")
snapshot.merge(["network_rx_bytes_per_sec": ["status": "measured", "value": 0.0, "unit": "B/s"],
                "network_tx_bytes_per_sec": ["status": "measured", "value": 0.0, "unit": "B/s"]], at: Date())
check(PrimaryMetric.network.title(in: snapshot) == "NET ↓0 ↑0 B/s", "measured zero network title")
snapshot.merge(["network_rx_bytes_per_sec": ["status": "unavailable", "unit": "B/s"],
                "network_tx_bytes_per_sec": ["status": "invalid", "unit": "B/s"]], at: Date())
check(PrimaryMetric.network.title(in: snapshot) == "NET ↓— ↑—", "invalid network became zero")

var records: [[String: Any]] = []
var updates = 0
var service: TelemetryService? = TelemetryService()
weak var weakService = service
service?.onUpdate = { _ in updates += 1 }
service?.reviewOnSample = { records.append($0) }
service?.start()
service?.start() // Must not create a second collector, observer, or scheduler.
check(updates == 1, "start duplicated initial publication")
NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
check(updates == 2, "duplicate thermal observer")
RunLoop.main.run(until: Date().addingTimeInterval(7.2))
service?.stop()
service?.stop()
check(records.count == 3, "duplicate or missing sampling after repeated start")
check(records.compactMap { $0["tick"] as? Int } == [1,2,3], "sample sequence duplicated")
check(records.last?["slow_count"] as? Int == 2, "slow cadence duplicated")
let stoppedUpdates = updates
NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
check(updates == stoppedUpdates, "thermal observer remained after stop")
service = nil
check(weakService == nil, "service retained by timer/observer/backend cycle")
print("METRIC_SERVICE_CHECKS PASS assertions=\(checks)")

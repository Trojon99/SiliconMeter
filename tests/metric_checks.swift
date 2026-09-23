// Appended to the production declarations by run-checks.sh, without the app entry point.
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !value() { fatalError(message) }
}
let uptime = ProcessInfo.processInfo.systemUptime
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
check(PrimaryMetric.gpuPower.title(in: snapshot) == "3W", "power primary mismatch")
check(PrimaryMetric.cpu.title(in: snapshot) == "C 50%", "CPU primary mismatch")
snapshot.merge(["gpuPower": raw("invalid")], at: Date())
check(PrimaryMetric.gpuPower.title(in: snapshot) == "—W", "invalid became zero power")
snapshot.merge(["total": raw("measured", 1)], at: Date(), uptime: uptime - 21)
check(PrimaryMetric.cpu.title(in: snapshot) == "C —", "queued old reading appeared fresh")

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

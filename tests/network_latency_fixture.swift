// Appended to production declarations in a review-only, collector-only executable.
import Foundation

let service = TelemetryService()
var latencies: [Double] = []
var intervals: [Double] = []
service.reviewOnSample = { record in
    if let value = record["sampling_latency_ms"] as? Double { latencies.append(value) }
    if let value = record["tick_interval_s"] as? Double { intervals.append(value) }
    if latencies.count == 60 {
        service.stop()
        let sorted = latencies.sorted()
        let output: [String: Any] = [
            "samples": latencies.count,
            "network_enabled": ProcessInfo.processInfo.environment["COMPUTE_MONITOR_NETWORK_DISABLED"] == nil,
            "mean_ms": latencies.reduce(0,+) / Double(latencies.count),
            "median_ms": (sorted[29] + sorted[30]) / 2,
            "p95_ms": sorted[56],
            "max_ms": sorted[59],
            "tick_interval_median_s": intervals.sorted()[29]
        ]
        let bytes = try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(data: bytes, encoding: .utf8)!)
        fflush(stdout)
        exit(0)
    }
}
service.start()
RunLoop.main.run(until: Date().addingTimeInterval(150))
fatalError("collector did not deliver 60 samples")

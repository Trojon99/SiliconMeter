// Appended to production declarations (without the AppKit entry point).
import SQLite3
import Darwin

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments[2]
func fail(_ message: String) -> Never { fatalError(message) }
func scalar(_ sql: String, readOnly: Bool = true) -> Int64? {
    var db: OpaquePointer?
    let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
    guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else { if let db { sqlite3_close(db) }; return nil }
    defer { sqlite3_close(db) }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(stmt) }
    return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
}
func awaitRows(_ count: Int64) {
    for _ in 0..<100 {
        if scalar("SELECT count(*) FROM fast_samples") == count { return }
        Thread.sleep(forTimeInterval: 0.02)
    }
    fail("timed out waiting for flush")
}
func metric(_ status: String, _ value: Any? = nil, _ window: Double? = nil) -> NSDictionary {
    var raw: [String: Any] = ["status": status, "source": "test", "unit": ""]
    if let value { raw["value"] = value }
    if let window { raw["window_s"] = window }
    return raw as NSDictionary
}
func snapshot(_ gpu: NSDictionary = metric("measured", 0.0), thermal: String = "Nominal",
              pressure: String = "Normal") -> TelemetrySnapshot {
    var s = TelemetrySnapshot()
    s.merge(["total": metric("measured", 0.5, 2), "p": metric("measured", 0.4, 2),
             "e": metric("unavailable"), "gpuActive": gpu,
             "gpuFrequency": metric("estimated", 960.0, 2),
             "network_rx_bytes_per_sec": metric("measured", 1250.0, 2),
             "network_tx_bytes_per_sec": metric("measured", 0.0, 2),
             "gpuPower": metric("estimated", 5.2, 6),
             "cpuTemperature": metric("measured", 60.0), "gpuTemperature": metric("measured", 65.0),
             "physical": metric("measured", 64_000_000_000.0), "free": metric("measured", 100.0),
             "active": metric("measured", 200.0), "inactive": metric("measured", 300.0),
             "wired": metric("measured", 400.0), "compressed": metric("measured", 500.0),
             "swapUsed": metric("measured", 0.0), "swapIn": metric("unavailable"),
             "swapOut": metric("unavailable"), "pressure": metric("measured", pressure),
             "thermal": metric("measured", thermal)], at: Date())
    return s
}
let logger = HistoryLogger(databaseURL: url)
logger.start(topologyVerified: true)
let t = Date(), uptime = ProcessInfo.processInfo.systemUptime
logger.observeStates(snapshot(), time: t, uptime: uptime)
logger.recordFast(snapshot(), seq: 1, time: t, uptime: uptime)
logger.recordSlow(snapshot(), seq: 0, time: t, uptime: uptime)
if mode == "normal" {
    logger.flushBeforeSleep()
    awaitRows(1)
    var reader: OpaquePointer?
    guard sqlite3_open_v2(url.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { fail("read-only open") }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(reader, "SELECT count(*) FROM fast_samples", -1, &stmt, nil) == SQLITE_OK,
          sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_int(stmt, 0) == 1 else { fail("read-only SELECT") }
    let changed = snapshot(metric("stale"), thermal: "Serious", pressure: "Warning")
    logger.recordFast(changed, seq: 2, time: Date(), uptime: ProcessInfo.processInfo.systemUptime)
    logger.observeStates(changed, time: Date(), uptime: ProcessInfo.processInfo.systemUptime)
    logger.flushBeforeSleep()
    awaitRows(2)
    guard sqlite3_column_int(stmt, 0) == 1 else { fail("WAL reader snapshot moved") }
    sqlite3_finalize(stmt); sqlite3_close(reader)
    logger.stop()
} else if mode == "crash" {
    logger.flushBeforeSleep()
    awaitRows(1)
    logger.recordFast(snapshot(metric("unavailable")), seq: 2, time: Date(), uptime: ProcessInfo.processInfo.systemUptime)
    Thread.sleep(forTimeInterval: 0.1)
    kill(getpid(), SIGKILL)
} else if mode == "resume" {
    logger.stop()
} else { fail("unknown mode") }

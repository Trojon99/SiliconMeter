import Foundation
import SQLite3
import Darwin

// All SQLite state is confined to writer. The collector and main thread only enqueue values.
final class HistoryLogger {
    static let schemaVersion = 1
    static let defaultFlushInterval: TimeInterval = 30
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Compute Monitor", isDirectory: true)
            .appendingPathComponent("telemetry.sqlite3")
    }

    private enum SQLValue {
        case text(String), number(Double), integer(Int64), null
    }
    private struct Row { let table: String; let values: [SQLValue] }
    private struct Field { let name: String; let key: String; let text: Bool }
    private static let fast: [Field] = [
        .init(name: "cpu_total", key: "total", text: false),
        .init(name: "cpu_p", key: "p", text: false),
        .init(name: "cpu_e", key: "e", text: false),
        .init(name: "gpu_active", key: "gpuActive", text: false),
        .init(name: "gpu_frequency_mhz", key: "gpuFrequency", text: false)
    ]
    private static let slow: [Field] = [
        .init(name: "gpu_power_w", key: "gpuPower", text: false),
        .init(name: "cpu_tp05_c", key: "cpuTemperature", text: false),
        .init(name: "gpu_tg05_c", key: "gpuTemperature", text: false),
        .init(name: "physical_b", key: "physical", text: false),
        .init(name: "free_b", key: "free", text: false),
        .init(name: "active_b", key: "active", text: false),
        .init(name: "inactive_b", key: "inactive", text: false),
        .init(name: "wired_b", key: "wired", text: false),
        .init(name: "compressed_b", key: "compressed", text: false),
        .init(name: "swap_used_b", key: "swapUsed", text: false),
        .init(name: "swap_in_pages_s", key: "swapIn", text: false),
        .init(name: "swap_out_pages_s", key: "swapOut", text: false),
        .init(name: "pressure", key: "pressure", text: true),
        .init(name: "thermal", key: "thermal", text: true)
    ]
    private let writer = DispatchQueue(label: "local.compute-monitor.history", qos: .utility)
    private let url: URL
    private let flushInterval: TimeInterval
    private let runID = UUID().uuidString
    private var db: OpaquePointer?
    private var pending: [Row] = []
    private var flushNumber = 0
    private var lastFlushUptime = ProcessInfo.processInfo.systemUptime
    private var active = false
    private var lastThermal: String?
    private var lastPressure: String?

    init(databaseURL: URL = HistoryLogger.defaultURL, flushInterval: TimeInterval = HistoryLogger.defaultFlushInterval) {
        url = databaseURL
        self.flushInterval = flushInterval
    }

    private static func ms(_ seconds: Double) -> Int64 { Int64((seconds * 1000).rounded()) }
    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unavailable" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "unavailable" }
        return String(cString: bytes)
    }
    private func execute(_ sql: String) -> Bool {
        guard let db else { return false }
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            fputs("History SQLite: \(error.map { String(cString: $0) } ?? "unknown error")\n", stderr)
            sqlite3_free(error)
            return false
        }
        return true
    }
    private static func sampleDDL(_ table: String, _ fields: [Field]) -> String {
        let columns = fields.flatMap { field in
            ["\(field.name) \(field.text ? "TEXT" : "REAL")",
             "\(field.name)_quality TEXT NOT NULL CHECK (\(field.name)_quality IN ('measured','estimated','unavailable','invalid','stale'))",
             "\(field.name)_window_s REAL"]
        }
        return "CREATE TABLE IF NOT EXISTS \(table) (run_id TEXT NOT NULL REFERENCES app_runs(run_id), seq INTEGER NOT NULL, utc_ms INTEGER NOT NULL, uptime_ms INTEGER NOT NULL, \(columns.joined(separator: ", ")), PRIMARY KEY (run_id, seq)) WITHOUT ROWID"
    }
    private func insert(_ row: Row) -> Bool {
        guard let db else { return false }
        let placeholders = Array(repeating: "?", count: row.values.count).joined(separator: ",")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO \(row.table) VALUES (\(placeholders))", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        for (offset, value) in row.values.enumerated() {
            let i = Int32(offset + 1)
            switch value {
            case .text(let s): _ = s.withCString { sqlite3_bind_text(stmt, i, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            case .number(let n): sqlite3_bind_double(stmt, i, n)
            case .integer(let n): sqlite3_bind_int64(stmt, i, n)
            case .null: sqlite3_bind_null(stmt, i)
            }
        }
        return sqlite3_step(stmt) == SQLITE_DONE
    }
    private static func cell(_ metric: Metric?, text: Bool) -> [SQLValue] {
        guard let metric else { return [.null, .text(Quality.unavailable.rawValue), .null] }
        let usable = metric.quality == .measured || metric.quality == .estimated
        let value: SQLValue
        if usable, case .number(let n)? = metric.value, !text, n.isFinite { value = .number(n) }
        else if usable, case .text(let s)? = metric.value, text { value = .text(s) }
        else { value = .null }
        let quality = valueIsNull(value) && usable ? Quality.invalid.rawValue : metric.quality.rawValue
        return [value, .text(quality), metric.window.map { .number($0) } ?? .null]
    }
    private static func valueIsNull(_ value: SQLValue) -> Bool {
        if case .null = value { return true }; return false
    }
    private func sample(_ table: String, fields: [Field], snapshot: TelemetrySnapshot,
                        seq: Int, time: Date, uptime: TimeInterval) {
        var values: [SQLValue] = [.text(runID), .integer(Int64(seq)),
                                  .integer(Self.ms(time.timeIntervalSince1970)), .integer(Self.ms(uptime))]
        for field in fields { values += Self.cell(snapshot[field.key], text: field.text) }
        let row = Row(table: table, values: values)
        writer.async { [self] in
            guard active else { return }
            pending.append(row)
            if uptime - lastFlushUptime >= flushInterval { flush() }
        }
    }
    func start(topologyVerified: Bool) {
        writer.async { [self] in
            do { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
            catch { fputs("History directory: \(error)\n", stderr); return }
            guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                fputs("History open: \(db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown")\n", stderr)
                if let db { sqlite3_close(db) }; db = nil; return
            }
            guard execute("PRAGMA journal_mode=WAL"), execute("PRAGMA synchronous=NORMAL"),
                  execute("PRAGMA foreign_keys=ON") else { close(); return }
            var version: Int32 = -1
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK,
               sqlite3_step(stmt) == SQLITE_ROW { version = sqlite3_column_int(stmt, 0) }
            sqlite3_finalize(stmt)
            guard version == 0 || version == Self.schemaVersion else {
                fputs("History schema version \(version) unsupported\n", stderr); close(); return
            }
            let ddl = [
                "CREATE TABLE IF NOT EXISTS app_runs (run_id TEXT PRIMARY KEY, start_utc_ms INTEGER NOT NULL, end_utc_ms INTEGER, app_version TEXT NOT NULL, build_version TEXT NOT NULL, schema_version INTEGER NOT NULL, macos_version TEXT NOT NULL, macos_build TEXT NOT NULL, hardware_id TEXT NOT NULL, logical_cores INTEGER NOT NULL, pe_topology_verified INTEGER NOT NULL)",
                Self.sampleDDL("fast_samples", Self.fast), Self.sampleDDL("slow_samples", Self.slow),
                "CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, run_id TEXT NOT NULL REFERENCES app_runs(run_id), utc_ms INTEGER NOT NULL, uptime_ms INTEGER NOT NULL, kind TEXT NOT NULL, old_value TEXT, new_value TEXT, quality TEXT NOT NULL)",
                "CREATE TABLE IF NOT EXISTS writer_batches (run_id TEXT NOT NULL REFERENCES app_runs(run_id), batch_seq INTEGER NOT NULL, utc_ms INTEGER NOT NULL, duration_ms REAL NOT NULL, fast_rows INTEGER NOT NULL, slow_rows INTEGER NOT NULL, event_rows INTEGER NOT NULL, PRIMARY KEY (run_id, batch_seq)) WITHOUT ROWID"
            ]
            guard execute("BEGIN IMMEDIATE"), ddl.allSatisfy({ execute($0) }),
                  execute("PRAGMA user_version=\(Self.schemaVersion)"), execute("COMMIT") else {
                _ = execute("ROLLBACK"); close(); return
            }
            let bundle = Bundle.main
            let row = Row(table: "app_runs", values: [.text(runID), .integer(Self.ms(Date().timeIntervalSince1970)), .null,
                .text(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"),
                .text(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"),
                .integer(Int64(Self.schemaVersion)), .text(ProcessInfo.processInfo.operatingSystemVersionString),
                .text(Self.sysctlString("kern.osversion")), .text(Self.sysctlString("hw.model")),
                .integer(Int64(ProcessInfo.processInfo.processorCount)), .integer(topologyVerified ? 1 : 0)])
            guard insert(row) else { fputs("History run insert failed\n", stderr); close(); return }
            active = true
            pending.append(Row(table: "events", values: [.null, .text(runID),
                .integer(Self.ms(Date().timeIntervalSince1970)),
                .integer(Self.ms(ProcessInfo.processInfo.systemUptime)),
                .text("app_start"), .null, .null, .text(Quality.measured.rawValue)]))
        }
    }
    func recordFast(_ snapshot: TelemetrySnapshot, seq: Int, time: Date, uptime: TimeInterval) {
        sample("fast_samples", fields: Self.fast, snapshot: snapshot, seq: seq, time: time, uptime: uptime)
    }
    func recordSlow(_ snapshot: TelemetrySnapshot, seq: Int, time: Date, uptime: TimeInterval) {
        sample("slow_samples", fields: Self.slow, snapshot: snapshot, seq: seq, time: time, uptime: uptime)
    }
    func observeStates(_ snapshot: TelemetrySnapshot, time: Date, uptime: TimeInterval) {
        func state(_ key: String) -> (String, Quality)? {
            guard let metric = snapshot[key], case .text(let value)? = metric.value,
                  metric.quality == .measured || metric.quality == .estimated else { return nil }
            return (value, metric.quality)
        }
        if let (current, quality) = state("thermal") {
            if let previous = lastThermal, previous != current {
                event("thermal_change", old: previous, new: current, quality: quality, time: time, uptime: uptime)
            }
            lastThermal = current
        }
        if let (current, quality) = state("pressure") {
            if let previous = lastPressure, previous != current {
                event("pressure_change", old: previous, new: current, quality: quality, time: time, uptime: uptime)
            }
            lastPressure = current
        }
    }
    private func event(_ kind: String, old: String?, new: String?, quality: Quality, time: Date, uptime: TimeInterval) {
        let row = Row(table: "events", values: [.null, .text(runID), .integer(Self.ms(time.timeIntervalSince1970)),
            .integer(Self.ms(uptime)), .text(kind), old.map { .text($0) } ?? .null,
            new.map { .text($0) } ?? .null, .text(quality.rawValue)])
        writer.async { [self] in if active { pending.append(row) } }
    }
    func flushBeforeSleep() { writer.async { [self] in flush() } }
    private func flush() {
        guard active, !pending.isEmpty else { return }
        let begin = ProcessInfo.processInfo.systemUptime
        guard execute("BEGIN IMMEDIATE") else {
            fputs("History recording disabled after transaction failure\n", stderr)
            pending.removeAll()
            close()
            return
        }
        let success = pending.allSatisfy { insert($0) }
        let counts = (pending.filter { $0.table == "fast_samples" }.count,
                      pending.filter { $0.table == "slow_samples" }.count,
                      pending.filter { $0.table == "events" }.count)
        let duration = (ProcessInfo.processInfo.systemUptime - begin) * 1000
        let batch = Row(table: "writer_batches", values: [.text(runID), .integer(Int64(flushNumber + 1)),
            .integer(Self.ms(Date().timeIntervalSince1970)), .number(duration),
            .integer(Int64(counts.0)), .integer(Int64(counts.1)), .integer(Int64(counts.2))])
        if success && insert(batch) && execute("COMMIT") {
            flushNumber += 1
            pending.removeAll(keepingCapacity: true)
            lastFlushUptime = ProcessInfo.processInfo.systemUptime
        } else {
            _ = execute("ROLLBACK")
            fputs("History recording disabled after batch failure\n", stderr)
            pending.removeAll()
            close()
        }
    }
    private func close() { if let db { sqlite3_close(db) }; db = nil; active = false }
    func stop() {
        writer.sync { [self] in
            guard active else { close(); return }
            let time = Date(), uptime = ProcessInfo.processInfo.systemUptime
            pending.append(Row(table: "events", values: [.null, .text(runID), .integer(Self.ms(time.timeIntervalSince1970)),
                .integer(Self.ms(uptime)), .text("app_graceful_stop"), .null, .null, .text(Quality.measured.rawValue)]))
            flush()
            guard active else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE app_runs SET end_utc_ms=? WHERE run_id=?", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, Self.ms(time.timeIntervalSince1970))
                _ = runID.withCString { sqlite3_bind_text(stmt, 2, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            close()
        }
    }
}

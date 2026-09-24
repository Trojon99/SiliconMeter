import Foundation
import SQLite3
import Darwin

enum HistoryRetention: Int, CaseIterable {
    case oneDay = 1, sevenDays = 7, thirtyDays = 30, forever = 0

    var days: Int? { self == .forever ? nil : rawValue }
    var labelKey: String {
        switch self {
        case .oneDay: return "1 Day"
        case .sevenDays: return "7 Days"
        case .thirtyDays: return "30 Days"
        case .forever: return "Forever"
        }
    }
    func isShorter(than other: Self) -> Bool {
        (days ?? Int.max) < (other.days ?? Int.max)
    }
    func cutoffMilliseconds(now: Date) -> Int64? {
        guard let days else { return nil }
        return Int64((now.timeIntervalSince1970 * 1000).rounded()) - Int64(days) * 86_400_000
    }
}

enum HistoryRetentionPreference {
    static let key = "historyRetentionDays"
    static let lastCleanupKey = "lastRetentionCleanupUTC"

    static func loadOrInitialize(databaseURL: URL, defaults: UserDefaults = .standard,
                                 fileManager: FileManager = .default) -> HistoryRetention {
        if let saved = defaults.object(forKey: key) as? Int,
           let retention = HistoryRetention(rawValue: saved) { return retention }
        // Existence is checked before the logger opens SQLite, not inferred
        // from row counts. An existing database always gets the safe default.
        let chosen: HistoryRetention = fileManager.fileExists(atPath: databaseURL.path) ? .forever : .thirtyDays
        defaults.set(chosen.rawValue, forKey: key)
        return chosen
    }

    static func save(_ retention: HistoryRetention, defaults: UserDefaults = .standard) {
        defaults.set(retention.rawValue, forKey: key)
    }

    static func select(_ requested: HistoryRetention, from current: HistoryRetention,
                       defaults: UserDefaults = .standard, confirmShortening: () -> Bool) -> HistoryRetention {
        guard requested != current else { return current }
        guard !requested.isShorter(than: current) || confirmShortening() else { return current }
        save(requested, defaults: defaults)
        // A confirmed shorter policy must be retried on launch if the app
        // exits before its immediate writer cleanup has finished.
        if requested.isShorter(than: current) { defaults.removeObject(forKey: lastCleanupKey) }
        return requested
    }
}

// All SQLite state is confined to writer. The collector and main thread only enqueue values.
final class HistoryLogger {
    static let schemaVersion = 4
    static let defaultFlushInterval: TimeInterval = 30
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SiliconMeter", isDirectory: true)
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
        .init(name: "gpu_frequency_mhz", key: "gpuFrequency", text: false),
        .init(name: "network_rx_bytes_per_sec", key: "network_rx_bytes_per_sec", text: false),
        .init(name: "network_tx_bytes_per_sec", key: "network_tx_bytes_per_sec", text: false)
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
    private let writer = DispatchQueue(label: "io.github.trojon99.siliconmeter.history", qos: .utility)
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
    private var retention: HistoryRetention
    private let retentionDefaults: UserDefaults
    private var cleanupGeneration = 0
    private var cleanupJob: CleanupJob?
    private let cleanupBatchSize = 5_000
    private let maintenanceInterval: TimeInterval = 24 * 60 * 60
#if RETENTION_TEST
    var testBatchDidCommit: ((Int) -> Void)?
    var testRowsDeletedBeforeCommit: ((Int) -> Void)?
#endif

    struct CleanupResult {
        let deleted: [String: Int]
        let transactions: Int
        let scannedBatches: Int
        let maxTransactionMs: Double
        let elapsedSeconds: Double
        let completed: Bool
    }
    private enum CleanupTable: Int, CaseIterable {
        case fast, slow, events, batches, runs
        var name: String {
            switch self {
            case .fast: return "fast_samples"
            case .slow: return "slow_samples"
            case .events: return "events"
            case .batches: return "writer_batches"
            case .runs: return "app_runs"
            }
        }
        var sequenceColumn: String { self == .batches ? "batch_seq" : "seq" }
    }
    private struct CleanupRow {
        let text: String?
        let sequence: Int64
        let timestamp: Int64
    }
    private struct CleanupJob {
        let cutoff: Int64
        let generation: Int
        let started: Double
        let completion: ((CleanupResult) -> Void)?
        var table: CleanupTable = .fast
        var textCursor: String? = nil
        var sequenceCursor: Int64 = -1
        var deleted: [String: Int] = [:]
        var transactions = 0
        var scannedBatches = 0
        var maxTransactionMs = 0.0
    }

    struct Status {
        let recording: Bool
        let sizeBytes: Int64
    }

    init(databaseURL: URL = HistoryLogger.defaultURL, flushInterval: TimeInterval = HistoryLogger.defaultFlushInterval,
         retention: HistoryRetention = .forever, retentionDefaults: UserDefaults = .standard) {
        url = databaseURL
        self.flushInterval = flushInterval
        self.retention = retention
        self.retentionDefaults = retentionDefaults
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
    private func scalarText(_ sql: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let value = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: value)
    }
    private func schemaVersion() -> Int32? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int(stmt, 0) : nil
    }
    private func coreSchemaPresent(hasNetwork: Bool) -> Bool {
        guard let db else { return false }
        func columns(_ table: String) -> [String]? {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            var result: [String] = []
            while true {
                switch sqlite3_step(stmt) {
                case SQLITE_ROW:
                    guard let value = sqlite3_column_text(stmt, 1) else { return nil }
                    result.append(String(cString: value))
                case SQLITE_DONE: return result
                default: return nil
                }
            }
        }
        func sampleColumns(_ fields: [Field]) -> [String] {
            ["run_id", "seq", "utc_ms", "uptime_ms"] + fields.flatMap {
                [$0.name, "\($0.name)_quality", "\($0.name)_window_s"]
            }
        }
        let expected: [(String, [String])] = [
            ("app_runs", ["run_id", "start_utc_ms", "end_utc_ms", "app_version", "build_version",
                          "schema_version", "macos_version", "macos_build", "hardware_id",
                          "logical_cores", "pe_topology_verified"]),
            ("fast_samples", sampleColumns(hasNetwork ? Self.fast : Array(Self.fast.prefix(5)))),
            ("slow_samples", sampleColumns(Self.slow)),
            ("events", ["id", "run_id", "utc_ms", "uptime_ms", "kind", "old_value", "new_value", "quality"]),
            ("writer_batches", ["run_id", "batch_seq", "utc_ms", "duration_ms", "fast_rows",
                                "slow_rows", "event_rows"])
        ]
        return expected.allSatisfy { name, expectedColumns in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            _ = name.withCString { sqlite3_bind_text(stmt, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            return sqlite3_step(stmt) == SQLITE_ROW && columns(name) == expectedColumns
        }
    }
    private func emptyDatabase() -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type IN ('table','view','index','trigger') AND name NOT LIKE 'sqlite_%' LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_DONE
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
            guard let version = schemaVersion(), (0...Self.schemaVersion).contains(Int(version)),
                  scalarText("PRAGMA integrity_check") == "ok",
                  (version == 0 ? emptyDatabase() : coreSchemaPresent(hasNetwork: version == Self.schemaVersion)) else {
                fputs("History schema or integrity check failed\n", stderr); close(); return
            }
            let ddl = [
                "CREATE TABLE IF NOT EXISTS app_runs (run_id TEXT PRIMARY KEY, start_utc_ms INTEGER NOT NULL, end_utc_ms INTEGER, app_version TEXT NOT NULL, build_version TEXT NOT NULL, schema_version INTEGER NOT NULL, macos_version TEXT NOT NULL, macos_build TEXT NOT NULL, hardware_id TEXT NOT NULL, logical_cores INTEGER NOT NULL, pe_topology_verified INTEGER NOT NULL)",
                Self.sampleDDL("fast_samples", Self.fast), Self.sampleDDL("slow_samples", Self.slow),
                "CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, run_id TEXT NOT NULL REFERENCES app_runs(run_id), utc_ms INTEGER NOT NULL, uptime_ms INTEGER NOT NULL, kind TEXT NOT NULL, old_value TEXT, new_value TEXT, quality TEXT NOT NULL)",
                "CREATE TABLE IF NOT EXISTS writer_batches (run_id TEXT NOT NULL REFERENCES app_runs(run_id), batch_seq INTEGER NOT NULL, utc_ms INTEGER NOT NULL, duration_ms REAL NOT NULL, fast_rows INTEGER NOT NULL, slow_rows INTEGER NOT NULL, event_rows INTEGER NOT NULL, PRIMARY KEY (run_id, batch_seq)) WITHOUT ROWID"
            ]
            let additions = ["network_rx_bytes_per_sec", "network_tx_bytes_per_sec"].flatMap { name in
                ["ALTER TABLE fast_samples ADD COLUMN \(name) REAL",
                 "ALTER TABLE fast_samples ADD COLUMN \(name)_quality TEXT NOT NULL DEFAULT 'unavailable' CHECK (\(name)_quality IN ('measured','estimated','unavailable','invalid','stale'))",
                 "ALTER TABLE fast_samples ADD COLUMN \(name)_window_s REAL"]
            }
            guard execute("BEGIN IMMEDIATE"), ddl.allSatisfy({ execute($0) }),
                  (version == 0 || version == Self.schemaVersion || additions.allSatisfy({ execute($0) })),
                  coreSchemaPresent(hasNetwork: true),
                  execute("PRAGMA user_version=\(Self.schemaVersion)"),
                  scalarText("PRAGMA integrity_check") == "ok", execute("COMMIT") else {
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
            startCleanupIfDue(now: Date(), force: false, completion: nil)
            scheduleMaintenanceCheck()
        }
    }

    // The daily delayed writer task is the only retention scheduler. It is not
    // attached to the 2-second collector or the sample/flush path.
    private func scheduleMaintenanceCheck() {
        guard active else { return }
        let now = Date().timeIntervalSince1970
        let last = retentionDefaults.double(forKey: HistoryRetentionPreference.lastCleanupKey)
        let elapsed = now - last
        let delay = last > 0 && elapsed >= 0 && elapsed < maintenanceInterval
            ? maintenanceInterval - elapsed : maintenanceInterval
        writer.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.active else { return }
            self.startCleanupIfDue(now: Date(), force: false, completion: nil)
            self.scheduleMaintenanceCheck()
        }
    }

    func changeRetention(to policy: HistoryRetention) {
        writer.async { [self] in
            retention = policy
            cleanupGeneration += 1
            cleanupJob = nil
            if policy != .forever { startCleanupIfDue(now: Date(), force: true, completion: nil) }
        }
    }

    // Test entry also permits an exact millisecond cutoff and completion wait.
    func requestCleanup(_ policy: HistoryRetention, now: Date, force: Bool,
                        completion: @escaping (CleanupResult) -> Void) {
        writer.async { [self] in
            retention = policy
            cleanupGeneration += 1
            cleanupJob = nil
            startCleanupIfDue(now: now, force: force, completion: completion)
        }
    }

    private func startCleanupIfDue(now: Date, force: Bool, completion: ((CleanupResult) -> Void)?) {
        guard active, let cutoff = retention.cutoffMilliseconds(now: now) else {
            completion?(CleanupResult(deleted: [:], transactions: 0, scannedBatches: 0,
                                      maxTransactionMs: 0, elapsedSeconds: 0, completed: true))
            return
        }
        let elapsed = now.timeIntervalSince1970 - retentionDefaults.double(forKey: HistoryRetentionPreference.lastCleanupKey)
        if !force && elapsed >= 0 && elapsed < maintenanceInterval { return }
        flush()
        cleanupGeneration += 1
        cleanupJob = CleanupJob(cutoff: cutoff, generation: cleanupGeneration,
                                started: ProcessInfo.processInfo.systemUptime, completion: completion)
        writer.async { [weak self] in self?.processCleanupBatch() }
    }

    private func selectCleanupRows(_ job: CleanupJob) -> [CleanupRow]? {
        guard let db else { return nil }
        let table = job.table
        let sql: String
        if table == .events {
            sql = "SELECT NULL,id,utc_ms FROM events WHERE id>? ORDER BY id LIMIT ?"
        } else if table == .runs {
            sql = job.textCursor == nil
                ? "SELECT run_id,0,start_utc_ms FROM app_runs ORDER BY run_id LIMIT ?"
                : "SELECT run_id,0,start_utc_ms FROM app_runs WHERE run_id>? ORDER BY run_id LIMIT ?"
        } else {
            let column = table.sequenceColumn
            sql = job.textCursor == nil
                ? "SELECT run_id,\(column),utc_ms FROM \(table.name) ORDER BY run_id,\(column) LIMIT ?"
                : "SELECT run_id,\(column),utc_ms FROM \(table.name) WHERE run_id>? OR (run_id=? AND \(column)>?) ORDER BY run_id,\(column) LIMIT ?"
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        if table == .events {
            sqlite3_bind_int64(stmt, 1, job.sequenceCursor)
            sqlite3_bind_int(stmt, 2, Int32(cleanupBatchSize))
        } else if let cursor = job.textCursor {
            _ = cursor.withCString { sqlite3_bind_text(stmt, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            if table == .runs { sqlite3_bind_int(stmt, 2, Int32(cleanupBatchSize)) }
            else {
                _ = cursor.withCString { sqlite3_bind_text(stmt, 2, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                sqlite3_bind_int64(stmt, 3, job.sequenceCursor)
                sqlite3_bind_int(stmt, 4, Int32(cleanupBatchSize))
            }
        } else { sqlite3_bind_int(stmt, 1, Int32(cleanupBatchSize)) }
        var rows: [CleanupRow] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { return rows }
            guard step == SQLITE_ROW else { return nil }
            let text = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
            rows.append(CleanupRow(text: text, sequence: sqlite3_column_int64(stmt, 1),
                                   timestamp: sqlite3_column_int64(stmt, 2)))
        }
    }

    private func hasLegacyTrainingSessions() -> Bool {
        scalarText("SELECT name FROM sqlite_master WHERE type='table' AND name='training_sessions'") != nil
    }

    private func deleteCleanupRows(_ rows: [CleanupRow], job: inout CleanupJob) -> Bool {
        guard let db else { return false }
        let candidates = rows.filter { $0.timestamp < job.cutoff }
        guard !candidates.isEmpty else { return true }
        let table = job.table
        let sql: String
        if table == .events {
            sql = "DELETE FROM events WHERE id=?1 AND utc_ms<?2"
        } else if table == .runs {
            sql = "DELETE FROM app_runs WHERE run_id=?1 AND run_id<>?2 AND COALESCE(end_utc_ms,start_utc_ms)<?3 " +
                  "AND NOT EXISTS (SELECT 1 FROM fast_samples WHERE run_id=?1) " +
                  "AND NOT EXISTS (SELECT 1 FROM slow_samples WHERE run_id=?1) " +
                  "AND NOT EXISTS (SELECT 1 FROM events WHERE run_id=?1) " +
                  "AND NOT EXISTS (SELECT 1 FROM writer_batches WHERE run_id=?1)" +
                  (hasLegacyTrainingSessions() ? " AND NOT EXISTS (SELECT 1 FROM training_sessions WHERE start_run_id=?1 OR end_run_id=?1)" : "")
        } else {
            sql = "DELETE FROM \(table.name) WHERE run_id=?1 AND \(table.sequenceColumn)=?2 AND utc_ms<?3"
        }
        let begun = ProcessInfo.processInfo.systemUptime
        guard execute("BEGIN IMMEDIATE") else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            _ = execute("ROLLBACK"); return false
        }
        var deleted = 0
        var okay = true
        for row in candidates {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            if let text = row.text {
                _ = text.withCString { sqlite3_bind_text(stmt, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            } else { sqlite3_bind_int64(stmt, 1, row.sequence) }
            if table == .runs {
                _ = runID.withCString { sqlite3_bind_text(stmt, 2, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                sqlite3_bind_int64(stmt, 3, job.cutoff)
            } else if table == .events { sqlite3_bind_int64(stmt, 2, job.cutoff) }
            else {
                sqlite3_bind_int64(stmt, 2, row.sequence)
                sqlite3_bind_int64(stmt, 3, job.cutoff)
            }
            if sqlite3_step(stmt) != SQLITE_DONE { okay = false; break }
            deleted += Int(sqlite3_changes(db))
#if RETENTION_TEST
            testRowsDeletedBeforeCommit?(deleted)
#endif
        }
        sqlite3_finalize(stmt)
        guard okay, execute("COMMIT") else { _ = execute("ROLLBACK"); return false }
        job.deleted[table.name, default: 0] += deleted
        job.transactions += 1
        job.maxTransactionMs = max(job.maxTransactionMs, (ProcessInfo.processInfo.systemUptime - begun) * 1000)
        return true
    }

    private func finishCleanup(_ job: CleanupJob, completed: Bool) {
        cleanupJob = nil
        if completed { retentionDefaults.set(Date().timeIntervalSince1970, forKey: HistoryRetentionPreference.lastCleanupKey) }
        else { fputs("History retention cleanup incomplete; will retry later\n", stderr) }
        job.completion?(CleanupResult(deleted: job.deleted, transactions: job.transactions,
                                      scannedBatches: job.scannedBatches,
                                      maxTransactionMs: job.maxTransactionMs,
                                      elapsedSeconds: ProcessInfo.processInfo.systemUptime - job.started,
                                      completed: completed))
    }

    private func processCleanupBatch() {
        guard active, var job = cleanupJob, job.generation == cleanupGeneration else { return }
        guard let rows = selectCleanupRows(job) else { finishCleanup(job, completed: false); return }
        if rows.isEmpty {
            guard let next = CleanupTable(rawValue: job.table.rawValue + 1) else {
                finishCleanup(job, completed: true); return
            }
            job.table = next
            job.textCursor = nil
            job.sequenceCursor = -1
        } else {
            job.scannedBatches += 1
            guard deleteCleanupRows(rows, job: &job) else { finishCleanup(job, completed: false); return }
#if RETENTION_TEST
            if job.transactions > 0 { testBatchDidCommit?(job.transactions) }
#endif
            job.textCursor = rows.last?.text
            job.sequenceCursor = rows.last!.sequence
        }
        cleanupJob = job
        writer.async { [weak self] in self?.processCleanupBatch() }
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
    func status(_ completion: @escaping (Status) -> Void) {
        writer.async { [self] in
            let bytes = ["", "-wal", "-shm"].reduce(Int64(0)) { total, suffix in
                let path = url.path + suffix
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
                return total + size
            }
            let result = Status(recording: active, sizeBytes: bytes)
            DispatchQueue.main.async { completion(result) }
        }
    }
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

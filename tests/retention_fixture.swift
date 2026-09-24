// App and HistoryLogger declarations are prepended by run-retention-checks.py.
import SQLite3
import Darwin

func require(_ okay: @autoclosure () -> Bool, _ message: String) {
    guard okay() else { fputs("RETENTION_FIXTURE_FAIL \(message)\n", stderr); exit(1) }
}

let arguments = CommandLine.arguments
let mode = arguments[1]
let url = URL(fileURLWithPath: arguments[2])
let suite = arguments[3]
let defaults = UserDefaults(suiteName: suite)!

if mode == "choose" {
    let from = HistoryRetention(rawValue: Int(arguments[4])!)!
    let to = HistoryRetention(rawValue: Int(arguments[5])!)!
    let accepted = arguments[6] == "accept"
    let selected = HistoryRetentionPreference.select(to, from: from, defaults: defaults) { accepted }
    require(selected == (accepted ? to : from), "selection result")
    print("RETENTION_CHOOSE selected=\(selected.rawValue)")
} else if mode == "preferences" {
    let fresh = url.appendingPathComponent("fresh.sqlite3")
    let existing = url.appendingPathComponent("existing.sqlite3")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    require(HistoryRetentionPreference.loadOrInitialize(databaseURL: fresh, defaults: defaults) == .thirtyDays, "fresh default")
    require(defaults.integer(forKey: HistoryRetentionPreference.key) == 30, "fresh persisted")
    defaults.set(Date().timeIntervalSince1970, forKey: HistoryRetentionPreference.lastCleanupKey)
    var confirmed = false
    let cancelled = HistoryRetentionPreference.select(.oneDay, from: .thirtyDays, defaults: defaults) {
        confirmed = true; return false
    }
    require(confirmed && cancelled == .thirtyDays, "shortening cancel")
    require(defaults.integer(forKey: HistoryRetentionPreference.key) == 30, "cancel wrote preference")
    require(defaults.object(forKey: HistoryRetentionPreference.lastCleanupKey) != nil, "cancel invalidated cleanup clock")
    let accepted = HistoryRetentionPreference.select(.oneDay, from: .thirtyDays, defaults: defaults) { true }
    require(accepted == .oneDay && defaults.integer(forKey: HistoryRetentionPreference.key) == 1, "confirmed shortening")
    require(defaults.object(forKey: HistoryRetentionPreference.lastCleanupKey) == nil, "shortening did not invalidate cleanup clock")
    for policy in HistoryRetention.allCases {
        HistoryRetentionPreference.save(policy, defaults: defaults)
        require(HistoryRetentionPreference.loadOrInitialize(databaseURL: fresh, defaults: defaults) == policy, "preference persistence")
    }
    defaults.removeObject(forKey: HistoryRetentionPreference.key)
    FileManager.default.createFile(atPath: existing.path, contents: Data())
    require(HistoryRetentionPreference.loadOrInitialize(databaseURL: existing, defaults: defaults) == .forever, "existing-db safe default")
    require(defaults.integer(forKey: HistoryRetentionPreference.key) == 0, "existing-db default persisted")
    require(HistoryRetentionPreference.loadOrInitialize(databaseURL: existing, defaults: defaults) == .forever, "idempotent existing default")
    let bundle = Bundle(path: arguments[4])!
    let en = Localizer(defaults: defaults, resources: bundle, preferredLanguages: ["en"])
    let zh = Localizer(defaults: defaults, resources: bundle, preferredLanguages: ["zh-Hans"])
    require(en.text("30 Days") == "30 Days" && zh.text("30 Days") == "30 天", "30-day localization")
    require(en.text("Forever") == "Forever" && zh.text("Forever") == "永久", "forever localization")
    require(zh.text("Delete Old History") == "删除旧记录", "confirmation localization")
    require(HistoryRetention.oneDay.isShorter(than: .sevenDays), "shorter ordering")
    require(!HistoryRetention.forever.isShorter(than: .thirtyDays), "forever ordering")
    print("RETENTION_PREFERENCES PASS fresh/existing/cancel/confirm/persistence/localization")
} else {
    let logger = HistoryLogger(databaseURL: url, retention: .forever, retentionDefaults: defaults)
    logger.start(topologyVerified: true)
    let nowMS = Int64(arguments.count > 4 ? arguments[4] : "0") ?? 0
    let now = nowMS > 0 ? Date(timeIntervalSince1970: Double(nowMS) / 1000) : Date()
    let uptime = ProcessInfo.processInfo.systemUptime
    var snapshot = TelemetrySnapshot()
    snapshot.merge(["total": ["status": "measured", "value": 0.5, "unit": "ratio"],
                    "thermal": ["status": "measured", "value": "Nominal", "unit": ""]], at: now)
    logger.observeStates(snapshot, time: now, uptime: uptime)
    logger.recordFast(snapshot, seq: 1, time: now, uptime: uptime)
    logger.recordSlow(snapshot, seq: 0, time: now, uptime: uptime)
    logger.flushBeforeSleep()
    if mode == "init" {
        logger.stop()
        print("RETENTION_INIT PASS")
    } else {
        let policy = HistoryRetention(rawValue: Int(arguments[5])!)!
        let killAfter = arguments.count > 6 ? Int(arguments[6])! : 0
        let concurrent = arguments.count > 7 && arguments[7] == "concurrent"
        var injected = false
        logger.testRowsDeletedBeforeCommit = { deleted in
            if killAfter < 0 && deleted >= -killAfter {
                print("RETENTION_KILL_INSIDE_TRANSACTION \(deleted)")
                fflush(stdout)
                kill(getpid(), SIGKILL)
            }
        }
        logger.testBatchDidCommit = { batch in
            if concurrent && !injected {
                injected = true
                var changed = snapshot
                changed.merge(["thermal": ["status": "measured", "value": "Serious", "unit": ""]], at: now)
                logger.recordFast(snapshot, seq: 2, time: now, uptime: uptime)
                logger.recordSlow(snapshot, seq: 2, time: now, uptime: uptime)
                logger.observeStates(changed, time: now, uptime: uptime)
                logger.flushBeforeSleep()
            }
            if killAfter > 0 && batch >= killAfter {
                print("RETENTION_KILL_AFTER_BATCH \(batch)")
                fflush(stdout)
                kill(getpid(), SIGKILL)
            }
        }
        let signal = DispatchSemaphore(value: 0)
        var result: HistoryLogger.CleanupResult?
        logger.requestCleanup(policy, now: now, force: true) { report in
            result = report
            signal.signal()
        }
        var lastHeartbeat = ProcessInfo.processInfo.systemUptime
        var maxHeartbeatGapMs = 0.0
        var heartbeatCount = 0
        let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            let current = ProcessInfo.processInfo.systemUptime
            maxHeartbeatGapMs = max(maxHeartbeatGapMs, (current - lastHeartbeat) * 1000)
            lastHeartbeat = current
            heartbeatCount += 1
        }
        let deadline = Date(timeIntervalSinceNow: 120)
        while signal.wait(timeout: .now()) != .success && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        heartbeat.invalidate()
        require(result != nil, "cleanup timed out")
        let walURL = URL(fileURLWithPath: url.path + "-wal")
        let walBytesBeforeStop = (try? FileManager.default.attributesOfItem(atPath: walURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        logger.stop()
        let report = result!
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let object: [String: Any] = ["completed": report.completed, "deleted": report.deleted,
                                     "transactions": report.transactions, "scanned_batches": report.scannedBatches,
                                     "max_transaction_ms": report.maxTransactionMs, "elapsed_s": report.elapsedSeconds,
                                     "main_heartbeat_count": heartbeatCount,
                                     "max_main_heartbeat_gap_ms": maxHeartbeatGapMs,
                                     "wal_bytes_before_stop": walBytesBeforeStop,
                                     "fixture_peak_rss_bytes": usage.ru_maxrss]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}

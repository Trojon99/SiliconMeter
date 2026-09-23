import AppKit
import Foundation

enum Quality: String {
    case measured, estimated, unavailable, invalid, stale
}

enum NetworkRateFormat {
    static func parts(_ bytesPerSecond: Double) -> (String, String) {
        let scale: Double
        let unit: String
        if bytesPerSecond >= 1_000_000_000 { scale = 1_000_000_000; unit = "GB/s" }
        else if bytesPerSecond >= 1_000_000 { scale = 1_000_000; unit = "MB/s" }
        else if bytesPerSecond >= 1_000 { scale = 1_000; unit = "KB/s" }
        else { scale = 1; unit = "B/s" }
        let value = bytesPerSecond / scale
        return (String(format: scale == 1 || value >= 100 ? "%.0f" : "%.1f", value), unit)
    }
    static func display(_ bytesPerSecond: Double) -> String {
        let (value, unit) = parts(bytesPerSecond)
        return "\(value) \(unit)"
    }
}

struct Metric {
    enum Value { case number(Double), text(String) }
    let value: Value?
    let unit: String
    let time: Date
    let observedUptime: TimeInterval
    let window: TimeInterval?
    let quality: Quality
    let source: String
    let reason: String?

    init(_ raw: NSDictionary, at time: Date, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let status = raw["status"] as? String ?? "invalid"
        quality = Quality(rawValue: status) ?? .invalid
        unit = raw["unit"] as? String ?? ""
        source = raw["source"] as? String ?? "unknown"
        reason = raw["reason"] as? String
        window = raw["window_s"] as? TimeInterval
        self.time = time
        observedUptime = uptime
        if let text = raw["value"] as? String { value = .text(text) }
        else if let number = raw["value"] as? NSNumber { value = .number(number.doubleValue) }
        else { value = nil }
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> Metric {
        let label: String
        switch state {
        case .nominal: label = "Nominal"
        case .fair: label = "Fair"
        case .serious: label = "Serious"
        case .critical: label = "Critical"
        @unknown default: label = "Unknown"
        }
        return Metric(["status": "measured", "source": "ProcessInfo.thermalState", "unit": "", "value": label], at: Date())
    }

    var display: String {
        let tr = Localizer.shared.text
        if isStale { return tr("Stale") }
        guard quality == .measured || quality == .estimated, let value else {
            return tr(quality == .stale ? "Stale" : quality == .invalid ? "Invalid" : "Unavailable")
        }
        let formatted: String
        switch value {
        case .text(let text): formatted = tr(text)
        case .number(let number):
            switch unit {
            case "ratio": formatted = String(format: "%.0f%%", number * 100)
            case "MHz": formatted = String(format: "%.0f MHz", number)
            case "W": formatted = String(format: "%.1f W", number)
            case "°C": formatted = String(format: "%.0f°C", number)
            case "B": formatted = ByteCountFormatter.string(fromByteCount: Int64(number), countStyle: .memory)
            case "B/s": formatted = NetworkRateFormat.display(number)
            case "pages/s": formatted = String(format: "%.1f %@", number, tr("pages/s"))
            case "events": formatted = String(format: "%.0f", number)
            default: formatted = String(format: "%.1f %@", number, unit)
            }
        }
        return quality == .estimated ? "\(formatted) \(tr("estimated"))" : formatted
    }

    var number: Double? {
        guard !isStale, quality == .measured || quality == .estimated else { return nil }
        if case .number(let n)? = value, n.isFinite { return n }
        return nil
    }

    private var isStale: Bool {
        source != "ProcessInfo.thermalState" && source != "hw.memsize" &&
        (quality == .measured || quality == .estimated) && ProcessInfo.processInfo.systemUptime - observedUptime > 20
    }
}

struct TelemetrySnapshot {
    var metrics: [String: Metric] = [:]
    mutating func merge(_ readings: NSDictionary, at time: Date, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        for (key, value) in readings {
            guard let key = key as? String, let raw = value as? NSDictionary else { continue }
            metrics[key] = Metric(raw, at: time, uptime: uptime)
        }
    }
    subscript(_ key: String) -> Metric? { metrics[key] }
}

enum PrimaryMetric: Int, CaseIterable {
    case cpu, gpu, temperature, gpuPower, network
    var label: String {
        let tr = Localizer.shared.text
        switch self { case .cpu: return tr("CPU"); case .gpu: return tr("GPU"); case .temperature: return tr("Temperature"); case .gpuPower: return tr("GPU Power"); case .network: return tr("Network") }
    }
    func title(in snapshot: TelemetrySnapshot) -> String {
        let tr = Localizer.shared.text
        switch self {
        case .cpu:
            guard let number = snapshot["total"]?.number else { return "\(tr("CPU")) —" }
            return String(format: "%@ %.0f%%", tr("CPU"), number * 100)
        case .gpu:
            guard let number = snapshot["gpuActive"]?.number else { return "\(tr("GPU")) —" }
            return String(format: "%@ %.0f%%", tr("GPU"), number * 100)
        case .temperature:
            guard let number = snapshot["cpuTemperature"]?.number else { return "\(tr("Temp")) —" }
            return String(format: "%@ %.0f°C", tr("Temp"), number)
        case .gpuPower:
            guard let number = snapshot["gpuPower"]?.number else { return "\(tr("GPU Power")) —" }
            if number < 99.95, number.rounded() != number { return String(format: "%@ %.1fW", tr("GPU Power"), number) }
            if number < 999.5 { return String(format: "%@ %.0fW", tr("GPU Power"), number) }
            return String(format: "%@ %.0fkW", tr("GPU Power"), number / 1000)
        case .network:
            let rx = snapshot["network_rx_bytes_per_sec"]?.number.map(NetworkRateFormat.parts)
            let tx = snapshot["network_tx_bytes_per_sec"]?.number.map(NetworkRateFormat.parts)
            if let rx, let tx, rx.1 == tx.1 { return "\(tr("NET")) ↓\(rx.0) ↑\(tx.0) \(rx.1)" }
            let received = rx.map { "\($0.0) \($0.1)" } ?? "—"
            let sent = tx.map { "\($0.0) \($0.1)" } ?? "—"
            return "\(tr("NET")) ↓\(received) ↑\(sent)"
        }
    }
}

final class TelemetryService {
    private let queue = DispatchQueue(label: "local.compute-monitor.collector", qos: .utility)
    private var backend: TelemetryBackend?
    private var timer: DispatchSourceTimer?
    private var ticks = 0
    private var stopped = false
    private var started = false
    private var thermalObserver: NSObjectProtocol?
    private(set) var snapshot = TelemetrySnapshot()
    var onUpdate: ((TelemetrySnapshot) -> Void)?
    var history: HistoryLogger?
#if STEP31_REVIEW
    var reviewOnSample: (([String: Any]) -> Void)?
    private var reviewLastTick = ProcessInfo.processInfo.systemUptime
#endif

    func start() {
        guard !started else { return }
        started = true
        snapshot.metrics["thermal"] = .thermal(ProcessInfo.processInfo.thermalState)
        history?.observeStates(snapshot, time: Date(), uptime: ProcessInfo.processInfo.systemUptime)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.snapshot.metrics["thermal"] = .thermal(ProcessInfo.processInfo.thermalState)
            self.history?.observeStates(self.snapshot, time: Date(), uptime: ProcessInfo.processInfo.systemUptime)
            self.onUpdate?(self.snapshot)
        }
        onUpdate?(snapshot)
        queue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let collector = TelemetryBackend()
                self.backend = collector
                self.history?.start(topologyVerified: collector.capabilities["topology"] == "measured")
                collector.pressureChanged = { [weak self] in
                    self?.queue.async { [weak self] in
                        guard let self, !self.stopped, let collector = self.backend else { return }
                        autoreleasepool { self.deliver(collector.samplePressure() as NSDictionary, kind: .pressure, seq: self.ticks) }
                    }
                }
                self.deliver(collector.sampleSlow() as NSDictionary, kind: .slow, seq: 0)
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                self.timer = timer
                timer.setEventHandler { [weak self] in self?.tick() }
                timer.resume()
                self.armTimer()
            }
        }
    }

    private func armTimer() {
        timer?.schedule(deadline: .now() + 2, leeway: .milliseconds(100))
    }

    private func tick() {
        guard !stopped, let backend else { return }
        autoreleasepool {
#if STEP31_REVIEW
            let begin = ProcessInfo.processInfo.systemUptime
#endif
            let readings = NSMutableDictionary(dictionary: backend.sampleFast())
            ticks += 1
            let includesSlow = ticks % 3 == 0
            if includesSlow { readings.addEntries(from: backend.sampleSlow()) }
            deliver(readings, kind: includesSlow ? .fastAndSlow : .fast, seq: ticks)
#if STEP31_REVIEW
            let end = ProcessInfo.processInfo.systemUptime
            let resources = backend.reviewResources()
            let record: [String: Any] = ["kind": "sample", "tick": ticks,
                "slow_count": 1 + ticks / 3, "tick_interval_s": begin - reviewLastTick,
                "sampling_latency_ms": (end - begin) * 1000, "resources": resources,
                "readings": readings, "uptime_s": end]
            reviewLastTick = begin
            DispatchQueue.main.async { [weak self] in self?.reviewOnSample?(record) }
#endif
        }
        // A one-shot timer is rearmed after collection; delayed ticks are never replayed.
        armTimer()
    }

    private enum DeliveryKind { case fast, slow, fastAndSlow, pressure }
    private func deliver(_ readings: NSDictionary, kind: DeliveryKind, seq: Int) {
        let time = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.snapshot.merge(readings, at: time, uptime: uptime)
            if kind == .fast || kind == .fastAndSlow {
                self.history?.recordFast(self.snapshot, seq: seq, time: time, uptime: uptime)
            }
            if kind == .slow || kind == .fastAndSlow {
                self.history?.recordSlow(self.snapshot, seq: seq, time: time, uptime: uptime)
            }
            if kind != .fast { self.history?.observeStates(self.snapshot, time: time, uptime: uptime) }
            self.onUpdate?(self.snapshot)
        }
    }

    func stop() {
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        queue.sync {
            stopped = true
            timer?.cancel(); timer = nil
            backend?.shutdown(); backend = nil
        }
    }
}

final class MonitorPopover: NSViewController {
    private let text = NSTextField(labelWithString: "")
    private let modeButtons = NSStackView()
    private let heading = NSTextField(labelWithString: "")
    private let historyHeading = NSTextField(labelWithString: "")
    private let recording = NSTextField(labelWithString: "")
    private let databaseSize = NSTextField(labelWithString: "")
    private let openFolder = NSButton(title: "", target: nil, action: nil)
    private let languageHeading = NSTextField(labelWithString: "")
    private let languages = NSPopUpButton()
    private let quit = NSButton(title: "", target: nil, action: nil)
    var onMode: ((PrimaryMetric) -> Void)?
    var onLanguage: ((AppLanguage) -> Void)?
    var onQuit: (() -> Void)?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 740))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14)
        ])
        heading.font = .boldSystemFont(ofSize: 14)
        stack.addArrangedSubview(heading)
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.maximumNumberOfLines = 0
        text.lineBreakMode = .byWordWrapping
        stack.addArrangedSubview(text)
        modeButtons.orientation = .horizontal
        modeButtons.spacing = 5
        for mode in PrimaryMetric.allCases {
            let button = NSButton(title: mode.label, target: self, action: #selector(selectMode(_:)))
            button.tag = mode.rawValue
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 10)
            modeButtons.addArrangedSubview(button)
        }
        stack.addArrangedSubview(modeButtons)
        historyHeading.font = .boldSystemFont(ofSize: 12)
        stack.addArrangedSubview(historyHeading)
        stack.addArrangedSubview(recording)
        stack.addArrangedSubview(databaseSize)
        openFolder.target = self
        openFolder.action = #selector(openDataFolder)
        openFolder.bezelStyle = .rounded
        stack.addArrangedSubview(openFolder)
        languageHeading.font = .boldSystemFont(ofSize: 12)
        stack.addArrangedSubview(languageHeading)
        languages.addItems(withTitles: [Localizer.shared.text("English"), Localizer.shared.text("Simplified Chinese")])
        languages.target = self
        languages.action = #selector(selectLanguage(_:))
        stack.addArrangedSubview(languages)
        quit.target = self
        quit.action = #selector(quitApp)
        quit.bezelStyle = .rounded
        stack.addArrangedSubview(quit)
        preferredContentSize = NSSize(width: 400, height: 740)
        view = root
    }

    @objc private func selectMode(_ button: NSButton) {
        guard let mode = PrimaryMetric(rawValue: button.tag) else { return }
        onMode?(mode)
    }
    @objc private func quitApp() { onQuit?() }
    @objc private func openDataFolder() { NSWorkspace.shared.open(HistoryLogger.defaultURL.deletingLastPathComponent()) }
    @objc private func selectLanguage(_ sender: NSPopUpButton) {
        onLanguage?(sender.indexOfSelectedItem == 1 ? .simplifiedChinese : .english)
    }

#if STEP31_REVIEW
    func reviewSelect(_ mode: PrimaryMetric) {
        (modeButtons.arrangedSubviews[mode.rawValue] as? NSButton)?.performClick(nil)
    }
#endif
#if STEP3_UI_SMOKE
    func smokeSelectLanguage(_ language: AppLanguage) {
        languages.selectItem(at: language == .simplifiedChinese ? 1 : 0)
        selectLanguage(languages)
    }
    func smokeContains(_ value: String) -> Bool {
        [heading, text, historyHeading, recording, databaseSize, languageHeading, quit].contains {
            $0.stringValue.contains(value)
        } || openFolder.title.contains(value)
    }
    func smokeLayoutFits() -> Bool {
        view.layoutSubtreeIfNeeded()
        return [heading, text, historyHeading, recording, databaseSize, openFolder,
                languageHeading, languages, quit].allSatisfy { control in
            let frame = control.convert(control.bounds, to: view)
            return frame.minX >= 0 && frame.maxX <= view.bounds.width
                && frame.minY >= 0 && frame.maxY <= view.bounds.height
        }
    }
#endif

    func update(_ snapshot: TelemetrySnapshot, selected: PrimaryMetric, history: HistoryLogger.Status?) {
        _ = view
        let tr = Localizer.shared.text
        heading.stringValue = tr("Compute Monitor")
        func line(_ label: String, _ key: String) -> String {
            let value = snapshot[key]?.display ?? tr("Unavailable")
            return "\(tr(label)): \(value)"
        }
        let lines = [
            tr("CPU"), line("Total", "total"), line("P-core", "p"), line("E-core", "e"), "",
            tr("GPU"), line("Active", "gpuActive"), line("Weighted freq.", "gpuFrequency"), line("Power", "gpuPower"), "",
            tr("Network"), line("Download", "network_rx_bytes_per_sec"),
            line("Upload", "network_tx_bytes_per_sec"), "",
            tr("Memory"), line("Physical", "physical"), line("Free", "free"),
            line("Active", "active"), line("Inactive", "inactive"),
            line("Wired", "wired"), line("Compressed", "compressed"),
            line("Pressure", "pressure"), line("Swap used", "swapUsed"),
            line("Swap in", "swapIn"), line("Swap out", "swapOut"), "",
            tr("Thermal"), line("CPU Tp05", "cpuTemperature"),
            line("GPU Tg05", "gpuTemperature"), line("System thermal", "thermal")
        ]
        let rendered = lines.joined(separator: "\n")
        if text.stringValue != rendered { text.stringValue = rendered }
        for case let button as NSButton in modeButtons.arrangedSubviews {
            guard let mode = PrimaryMetric(rawValue: button.tag) else { continue }
            let title = mode == selected ? "✓ \(mode.label)" : mode.label
            if button.title != title { button.title = title }
        }
        historyHeading.stringValue = tr("History")
        recording.stringValue = "\(tr("Recording")): \(history?.recording == true ? tr("On") : tr("Unavailable"))"
        databaseSize.stringValue = "\(tr("Database Size")): \(history.map { ByteCountFormatter.string(fromByteCount: $0.sizeBytes, countStyle: .file) } ?? tr("Unavailable"))"
        openFolder.title = tr("Open Data Folder")
        languageHeading.stringValue = tr("Language")
        languages.item(at: 0)?.title = tr("English")
        languages.item(at: 1)?.title = tr("Simplified Chinese")
        languages.selectItem(at: Localizer.shared.language == .simplifiedChinese ? 1 : 0)
        quit.title = tr("Quit")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = TelemetryService()
    private let history = HistoryLogger()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let content = MonitorPopover()
    private var historyStatus: HistoryLogger.Status?
#if STEP31_REVIEW
    private let review = Step31Review()
#endif
    private var selected = PrimaryMetric(rawValue: UserDefaults.standard.integer(forKey: "primaryMetric")) ?? .cpu

    func applicationDidFinishLaunching(_ notification: Notification) {
        service.history = history
        NSApp.setActivationPolicy(.accessory)
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = content
        content.onMode = { [weak self] mode in
            guard let self else { return }
            self.selected = mode
#if !STEP31_REVIEW
            UserDefaults.standard.set(mode.rawValue, forKey: "primaryMetric")
#endif
            self.render(self.service.snapshot)
        }
        content.onQuit = { NSApp.terminate(nil) }
        content.onLanguage = { [weak self] language in
            guard let self else { return }
            Localizer.shared.select(language)
            self.render(self.service.snapshot)
        }
        statusItem.button?.title = selected.title(in: service.snapshot)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        service.onUpdate = { [weak self] snapshot in self?.render(snapshot) }
#if STEP31_REVIEW
        service.reviewOnSample = { [weak self] record in
            guard let self else { return }
            self.review.observe(record, snapshot: self.service.snapshot,
                isShown: { self.popover.isShown }, toggle: { self.togglePopover() },
                select: { self.content.reviewSelect($0) }, selected: { self.selected },
                title: { self.statusItem.button?.title ?? "" })
        }
#endif
        service.start()
#if STEP3_UI_SMOKE
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in self?.runUISmoke() }
#endif
    }

    private func render(_ snapshot: TelemetrySnapshot) {
        let title = selected.title(in: snapshot)
        if statusItem.button?.title != title { statusItem.button?.title = title }
        if popover.isShown { content.update(snapshot, selected: selected, history: historyStatus) }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.close() }
        else {
            content.update(service.snapshot, selected: selected, history: historyStatus)
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            history.status { [weak self] status in
                guard let self else { return }
                self.historyStatus = status
                self.render(self.service.snapshot)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.stop()
        history.stop()
    }

#if STEP3_UI_SMOKE
    private func runUISmoke() {
        let initial = statusItem.button?.title ?? ""
        let priorLanguage = UserDefaults.standard.string(forKey: Localizer.preferenceKey)
        let priorPrimary = UserDefaults.standard.object(forKey: "primaryMetric")
        togglePopover()
        let opened = popover.isShown
        let switched = PrimaryMetric.allCases.allSatisfy { mode in
            content.onMode?(mode)
            return selected == mode && statusItem.button?.title == mode.title(in: service.snapshot)
        }
        let variableWidth = statusItem.length == NSStatusItem.variableLength
        let boundaryFits = ["CPU 100%", "GPU 100%", "Temp 100°C", "GPU Power 99.9W", "温度 100°C", "GPU 功耗 99.9W", "NET ↓999.9 ↑999.9 MB/s", "NET ↓1.2 MB/s ↑420 KB/s"].allSatisfy { title in
            guard let button = statusItem.button, let font = button.font else { return false }
            button.title = title
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
            return button.bounds.width >= textWidth
        }
        let compactPowerFits = boundaryFits
        let cpuValue = service.snapshot["total"]?.number
        let gpuValue = service.snapshot["gpuActive"]?.number
        content.smokeSelectLanguage(.simplifiedChinese)
        var invalidSample = TelemetrySnapshot()
        invalidSample.merge(["gpuPower": ["status": "invalid", "unit": "W"]], at: Date())
        let estimate = Metric(["status": "estimated", "value": 14.0, "unit": "W", "source": "fixture"], at: Date())
        let chinese = statusItem.button?.title == selected.title(in: service.snapshot)
            && content.smokeContains("历史记录") && content.smokeContains("记录状态")
            && content.smokeContains("数据库大小") && content.smokeContains("打开数据文件夹")
            && PrimaryMetric.temperature.title(in: service.snapshot).hasPrefix("温度 ")
            && PrimaryMetric.gpuPower.title(in: service.snapshot).hasPrefix("GPU 功耗 ")
            && PrimaryMetric.gpuPower.title(in: invalidSample) == "GPU 功耗 —"
            && estimate.display.contains("估算")
            && content.smokeContains("网络") && content.smokeContains("下载") && content.smokeContains("上传")
            && PrimaryMetric.network.title(in: service.snapshot).hasPrefix("NET ↓")
            && content.smokeLayoutFits()
        content.smokeSelectLanguage(.english)
        let english = statusItem.button?.title == selected.title(in: service.snapshot)
            && content.smokeContains("History") && content.smokeContains("Recording")
            && content.smokeContains("Database Size") && content.smokeContains("Open Data Folder")
            && PrimaryMetric.temperature.title(in: service.snapshot).hasPrefix("Temp ")
            && PrimaryMetric.gpuPower.title(in: service.snapshot).hasPrefix("GPU Power ")
            && PrimaryMetric.gpuPower.title(in: invalidSample) == "GPU Power —"
            && estimate.display.contains("estimated")
            && content.smokeContains("Network") && content.smokeContains("Download") && content.smokeContains("Upload")
            && PrimaryMetric.network.title(in: service.snapshot).hasPrefix("NET ↓")
            && content.smokeLayoutFits()
        let telemetryUnchanged = service.snapshot["total"]?.number == cpuValue
            && service.snapshot["gpuActive"]?.number == gpuValue
        if let priorLanguage, let language = AppLanguage(rawValue: priorLanguage) {
            Localizer.shared.select(language)
        } else {
            UserDefaults.standard.removeObject(forKey: Localizer.preferenceKey)
        }
        if let priorPrimary { UserDefaults.standard.set(priorPrimary, forKey: "primaryMetric") }
        else { UserDefaults.standard.removeObject(forKey: "primaryMetric") }
        render(service.snapshot)
        togglePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let closed = !self.popover.isShown
            let accessory = NSApp.activationPolicy() == .accessory
            let cpuLive = self.service.snapshot["total"]?.number != nil
            let gpuLive = self.service.snapshot["gpuActive"]?.number != nil
            let passed = opened && switched && variableWidth && boundaryFits && compactPowerFits && chinese && english && telemetryUnchanged && closed && accessory && cpuLive && gpuLive
            print("UI_SMOKE opened=\(opened) switched=\(switched) variable_width=\(variableWidth) boundary_fits=\(boundaryFits) chinese=\(chinese) english=\(english) telemetry_unchanged=\(telemetryUnchanged) closed=\(closed) accessory=\(accessory) cpu=\(cpuLive) gpu=\(gpuLive) initial=\(initial) result=\(passed ? "PASS" : "FAIL")")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }
#endif
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

import AppKit
import Foundation

enum Quality: String {
    case measured, estimated, unavailable, invalid, stale
}

enum NetworkRateFormat {
    static let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s", "PB/s", "EB/s"]
    static let widestTemplate = "-1.0e+308 B/s"
    static func parts(_ bytesPerSecond: Double) -> (String, String) {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return ("—", "B/s") }
        if bytesPerSecond > 0, bytesPerSecond < 1 { return ("<1", "B/s") }
        var value = bytesPerSecond
        var unitIndex = 0
        while value >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }
        // Promote before one-decimal rounding could print 1000.0 in the old unit.
        if value >= (unitIndex == 0 ? 999.5 : 999.95), unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }
        if unitIndex == units.count - 1, value >= 999.95 {
            return (String(format: "%.1e", bytesPerSecond), "B/s")
        }
        let whole = value.rounded() == value
        return (String(format: unitIndex == 0 || (value >= 100 && whole) ? "%.0f" : "%.1f", value), units[unitIndex])
    }
    static func display(_ bytesPerSecond: Double) -> String {
        let (value, unit) = parts(bytesPerSecond)
        return "\(value) \(unit)"
    }
}

enum StatusPowerFormat {
    static let widestTemplate = "999.9kW"
    private static let units = ["W", "kW", "MW", "GW", "TW", "PW", "EW"]
    static func display(_ watts: Double) -> String {
        guard watts.isFinite else { return "—" }
        var value = abs(watts)
        var unitIndex = 0
        while value >= 999.95, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }
        if unitIndex == units.count - 1, value >= 999.95 {
            return String(format: "%.1eW", watts)
        }
        return String(format: "%.1f%@", watts < 0 ? -value : value, units[unitIndex])
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
    func statusFields(in snapshot: TelemetrySnapshot) -> [String] {
        switch self {
        case .cpu:
            return [snapshot["total"]?.number.map { String(format: "%.0f%%", $0 * 100) } ?? "—"]
        case .gpu:
            return [snapshot["gpuActive"]?.number.map { String(format: "%.0f%%", $0 * 100) } ?? "—"]
        case .temperature:
            return [snapshot["cpuTemperature"]?.number.map { String(format: "%.0f°C", $0) } ?? "—"]
        case .gpuPower:
            return [snapshot["gpuPower"]?.number.map(StatusPowerFormat.display) ?? "—"]
        case .network:
            return [snapshot["network_rx_bytes_per_sec"]?.number.map(NetworkRateFormat.display) ?? "—",
                    snapshot["network_tx_bytes_per_sec"]?.number.map(NetworkRateFormat.display) ?? "—"]
        }
    }
    var statusPrefix: String {
        let tr = Localizer.shared.text
        switch self {
        case .cpu: return tr("CPU")
        case .gpu: return tr("GPU")
        case .temperature: return tr("Temp")
        case .gpuPower: return tr("GPU Power")
        case .network: return "\(tr("NET")) ↓"
        }
    }
    func title(in snapshot: TelemetrySnapshot) -> String {
        let fields = statusFields(in: snapshot)
        if self == .network { return "\(statusPrefix) \(fields[0]) ↑ \(fields[1])" }
        return "\(statusPrefix) \(fields[0])"
    }
}

// Keep the status item fixed, but center a compact group inside it. Slot widths
// are cached by displayed number shape (digit count/unit), so ordinary updates
// only select measured widths and never measure text on the collection path.
struct StatusTitleLayout {
    let metric: PrimaryMetric
    let length: CGFloat
    private let prefix: String
    private let font: NSFont
    private let prefixWidth: CGFloat
    private let downWidth: CGFloat
    private let upWidth: CGFloat
    private let maximumSlot: CGFloat
    private let slotWidths: [String: CGFloat]
    private let inset: CGFloat = 8
    private let labelGap: CGFloat = 3
    private let outerScalarGap: CGFloat = 5 // Preserve the existing fixed item width.
    private let networkLabelGap: CGFloat = 6
    private let arrowGap: CGFloat = 3
    private let networkGroupGap: CGFloat = 7

    private static func shape(_ value: String) -> String {
        String(value.map { $0 >= "0" && $0 <= "9" ? "8" : $0 })
    }

    init(metric: PrimaryMetric, font: NSFont) {
        self.metric = metric
        self.font = font
        prefix = metric == .network ? Localizer.shared.text("NET") : metric.statusPrefix
        func width(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        prefixWidth = width(prefix)
        downWidth = width("↓")
        upWidth = width("↑")
        var widths: [String: CGFloat] = ["—": width("—")]
        func add(_ template: String) {
            widths[Self.shape(template)] = width(template)
        }
        switch metric {
        case .cpu, .gpu:
            add("100%")
        case .temperature:
            add("100°C")
        case .gpuPower:
            for unit in ["W", "kW", "MW", "GW", "TW", "PW", "EW"] {
                for number in ["8.8", "88.8", "888.8", "-8.8", "-88.8", "-888.8"] {
                    add(number + unit)
                }
            }
            for exponent in ["8", "88", "888"] {
                add("8.8e+\(exponent)W")
                add("-8.8e+\(exponent)W")
            }
        case .network:
            for unit in NetworkRateFormat.units {
                for number in ["8", "88", "888", "8.8", "88.8", "888.8", "<8"] {
                    add("\(number) \(unit)")
                }
            }
            for exponent in ["8", "88", "888"] {
                add("8.8e+\(exponent) B/s")
            }
        }
        slotWidths = widths
        maximumSlot = max(widths.values.max() ?? 0, width("—"))
        let contentWidth = metric == .network
            ? prefixWidth + networkLabelGap + downWidth + arrowGap + maximumSlot +
              networkGroupGap + upWidth + arrowGap + maximumSlot
            : prefixWidth + outerScalarGap + maximumSlot
        length = ceil(contentWidth + 2 * inset)
    }

    var scalarSlotWidth: CGFloat { maximumSlot }

    func slotWidth(for value: String) -> CGFloat {
        slotWidths[Self.shape(value)] ?? maximumSlot
    }

    func attributedTitle(in snapshot: TelemetrySnapshot) -> NSAttributedString {
        let fields = metric.statusFields(in: snapshot)
        let firstSlot = metric == .network ? slotWidth(for: fields[0]) : maximumSlot
        let secondSlot = metric == .network ? slotWidth(for: fields[1]) : 0
        let groupWidth = metric == .network
            ? prefixWidth + networkLabelGap + downWidth + arrowGap + firstSlot +
              networkGroupGap + upWidth + arrowGap + secondSlot
            : prefixWidth + labelGap + firstSlot
        let start = inset + max(0, (length - 2 * inset - groupWidth) / 2)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.firstLineHeadIndent = start
        if metric == .network {
            let downStart = start + prefixWidth + networkLabelGap
            let firstEnd = downStart + downWidth + arrowGap + firstSlot
            let upStart = firstEnd + networkGroupGap
            let secondEnd = upStart + upWidth + arrowGap + secondSlot
            paragraph.tabStops = [
                NSTextTab(textAlignment: .left, location: downStart),
                NSTextTab(textAlignment: .right, location: firstEnd),
                NSTextTab(textAlignment: .left, location: upStart),
                NSTextTab(textAlignment: .right, location: secondEnd)
            ]
        } else {
            paragraph.tabStops = [NSTextTab(textAlignment: .left,
                location: start + prefixWidth + labelGap)]
        }
        let text = metric == .network
            ? "\(prefix)\t↓\t\(fields[0])\t↑\t\(fields[1])"
            : "\(prefix)\t\(fields[0])"
        return NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
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
    private let statusItem = NSStatusBar.system.statusItem(withLength: 1)
    private let popover = NSPopover()
    private let content = MonitorPopover()
    private var historyStatus: HistoryLogger.Status?
    private var statusLayout: StatusTitleLayout?
    private var statusLayouts: [String: StatusTitleLayout] = [:]
    private var lastStatusText: String?
#if STEP3_UI_SMOKE
    private var statusLayoutMeasurements = 0
#endif
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
            self.configureStatusLayout()
            self.render(self.service.snapshot)
        }
        content.onQuit = { NSApp.terminate(nil) }
        content.onLanguage = { [weak self] language in
            guard let self else { return }
            Localizer.shared.select(language)
            self.configureStatusLayout()
            self.render(self.service.snapshot)
        }
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.button?.alignment = .left
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        configureStatusLayout()
        render(service.snapshot)
        service.onUpdate = { [weak self] snapshot in self?.render(snapshot) }
#if STEP31_REVIEW
        service.reviewOnSample = { [weak self] record in
            guard let self else { return }
            self.review.observe(record, snapshot: self.service.snapshot,
                isShown: { self.popover.isShown }, toggle: { self.togglePopover() },
                select: { self.content.reviewSelect($0) }, selected: { self.selected },
                title: { self.selected.title(in: self.service.snapshot) })
        }
#endif
        service.start()
#if STEP3_UI_SMOKE
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in self?.runUISmoke() }
#endif
    }

    private func render(_ snapshot: TelemetrySnapshot) {
        if let button = statusItem.button, let statusLayout {
            let title = statusLayout.attributedTitle(in: snapshot)
            if lastStatusText != title.string {
                button.attributedTitle = title
                button.setAccessibilityLabel(selected.title(in: snapshot))
                lastStatusText = title.string
            }
        }
        if popover.isShown { content.update(snapshot, selected: selected, history: historyStatus) }
    }

    private func configureStatusLayout() {
        guard let button = statusItem.button, let font = button.font else { return }
        let key = "\(Localizer.shared.language.rawValue):\(selected.rawValue)"
        if let cached = statusLayouts[key] {
            statusLayout = cached
        } else {
            let measured = StatusTitleLayout(metric: selected, font: font)
            statusLayouts[key] = measured
            statusLayout = measured
#if STEP3_UI_SMOKE
            statusLayoutMeasurements += 1
#endif
        }
        statusItem.length = statusLayout!.length
        lastStatusText = nil
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
    private func smokeWidthStable() -> Bool {
        guard let button = statusItem.button else { return false }
        func snapshot(_ mode: PrimaryMetric, _ first: Double?, _ second: Double? = nil) -> TelemetrySnapshot {
            var sample = service.snapshot
            func raw(_ number: Double?, _ unit: String) -> [String: Any] {
                var reading: [String: Any] = ["status": number == nil ? "unavailable" : "measured", "unit": unit, "source": "smoke"]
                if let number { reading["value"] = number }
                return reading
            }
            let values: [String: Any]
            switch mode {
            case .cpu: values = ["total": raw(first, "ratio")]
            case .gpu: values = ["gpuActive": raw(first, "ratio")]
            case .temperature: values = ["cpuTemperature": raw(first, "°C")]
            case .gpuPower: values = ["gpuPower": raw(first, "W")]
            case .network: values = ["network_rx_bytes_per_sec": raw(first, "B/s"),
                                     "network_tx_bytes_per_sec": raw(second, "B/s")]
            }
            sample.merge(values as NSDictionary, at: Date())
            return sample
        }
        for language in AppLanguage.allCases {
            content.smokeSelectLanguage(language)
            for mode in PrimaryMetric.allCases {
                content.onMode?(mode)
                let fixed = statusItem.length
                let measurements = statusLayoutMeasurements
                let values: [(Double?, Double?)]
                switch mode {
                case .cpu, .gpu: values = [(0,nil),(0.09,nil),(1,nil),(nil,nil)]
                case .temperature: values = [(9,nil),(61,nil),(100,nil),(nil,nil)]
                case .gpuPower: values = [(0,nil),(9.9,nil),(10,nil),(99.9,nil),(nil,nil)]
                case .network: values = [(0,0),(999_900,999_900),(1_000_000_000,1_000_000_000),(nil,nil)]
                }
                for (first,second) in values {
                    render(snapshot(mode,first,second))
                    RunLoop.main.run(until: Date().addingTimeInterval(0.025))
                    button.layoutSubtreeIfNeeded()
                    if abs(statusItem.length-fixed) > 0.01 || abs(button.frame.width-fixed) > 0.5
                        || statusLayoutMeasurements != measurements {
                        return false
                    }
                }
                render(service.snapshot)
            }
        }
        let measurements = statusLayoutMeasurements
        content.smokeSelectLanguage(.english)
        content.onMode?(.cpu)
        return statusLayoutMeasurements == measurements
    }

    private func runUISmoke() {
        let initial = selected.title(in: service.snapshot)
        let priorLanguage = UserDefaults.standard.string(forKey: Localizer.preferenceKey)
        let priorPrimary = UserDefaults.standard.object(forKey: "primaryMetric")
        let priorMode = selected
        let priorActiveLanguage = Localizer.shared.language
        togglePopover()
        let opened = popover.isShown
        let switched = PrimaryMetric.allCases.allSatisfy { mode in
            content.onMode?(mode)
            return selected == mode && statusItem.length > 0
                && statusItem.button?.attributedTitle.string == statusLayout?.attributedTitle(in: service.snapshot).string
        }
        let fixedWidth = statusItem.length != NSStatusItem.variableLength && smokeWidthStable()
        let cpuValue = service.snapshot["total"]?.number
        let gpuValue = service.snapshot["gpuActive"]?.number
        content.smokeSelectLanguage(.simplifiedChinese)
        var invalidSample = TelemetrySnapshot()
        invalidSample.merge(["gpuPower": ["status": "invalid", "unit": "W"]], at: Date())
        let estimate = Metric(["status": "estimated", "value": 14.0, "unit": "W", "source": "fixture"], at: Date())
        let chinese = statusItem.button?.attributedTitle.string == statusLayout?.attributedTitle(in: service.snapshot).string
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
        let english = statusItem.button?.attributedTitle.string == statusLayout?.attributedTitle(in: service.snapshot).string
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
        Localizer.shared.select(priorActiveLanguage)
        if priorLanguage == nil { UserDefaults.standard.removeObject(forKey: Localizer.preferenceKey) }
        if let priorPrimary { UserDefaults.standard.set(priorPrimary, forKey: "primaryMetric") }
        else { UserDefaults.standard.removeObject(forKey: "primaryMetric") }
        selected = priorMode
        configureStatusLayout()
        render(service.snapshot)
        togglePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let closed = !self.popover.isShown
            let accessory = NSApp.activationPolicy() == .accessory
            let cpuLive = self.service.snapshot["total"]?.number != nil
            let gpuLive = self.service.snapshot["gpuActive"]?.number != nil
            let passed = opened && switched && fixedWidth && chinese && english && telemetryUnchanged && closed && accessory && cpuLive && gpuLive
            print("UI_SMOKE opened=\(opened) switched=\(switched) fixed_width=\(fixedWidth) chinese=\(chinese) english=\(english) telemetry_unchanged=\(telemetryUnchanged) closed=\(closed) accessory=\(accessory) cpu=\(cpuLive) gpu=\(gpuLive) initial=\(initial) result=\(passed ? "PASS" : "FAIL")")
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

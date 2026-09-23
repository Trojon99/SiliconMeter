import AppKit
import Foundation

enum Quality: String {
    case measured, estimated, unavailable, invalid, stale
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
        if isStale { return "Stale" }
        guard quality == .measured || quality == .estimated, let value else {
            return quality == .stale ? "Stale" : quality == .invalid ? "Invalid" : "Unavailable"
        }
        let formatted: String
        switch value {
        case .text(let text): formatted = text
        case .number(let number):
            switch unit {
            case "ratio": formatted = String(format: "%.0f%%", number * 100)
            case "MHz": formatted = String(format: "%.0f MHz", number)
            case "W": formatted = String(format: "%.1f W", number)
            case "°C": formatted = String(format: "%.0f°C", number)
            case "B": formatted = ByteCountFormatter.string(fromByteCount: Int64(number), countStyle: .memory)
            case "pages/s": formatted = String(format: "%.1f pages/s", number)
            case "events": formatted = String(format: "%.0f", number)
            default: formatted = String(format: "%.1f %@", number, unit)
            }
        }
        return quality == .estimated ? "\(formatted) estimated" : formatted
    }

    var number: Double? {
        guard !isStale, quality == .measured || quality == .estimated else { return nil }
        if case .number(let n)? = value { return n }
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
    case cpu, gpu, temperature, gpuPower
    var label: String {
        switch self { case .cpu: "CPU"; case .gpu: "GPU"; case .temperature: "Temperature"; case .gpuPower: "GPU power" }
    }
    func title(in snapshot: TelemetrySnapshot) -> String {
        switch self {
        case .cpu:
            guard let number = snapshot["total"]?.number else { return "CPU —" }
            return String(format: "CPU %.0f%%", number * 100)
        case .gpu:
            guard let number = snapshot["gpuActive"]?.number else { return "GPU —" }
            return String(format: "GPU %.0f%%", number * 100)
        case .temperature:
            guard let number = snapshot["cpuTemperature"]?.number else { return "Temp —" }
            return String(format: "Temp %.0f°C", number)
        case .gpuPower:
            guard let number = snapshot["gpuPower"]?.number else { return "GPU Power —" }
            let watts = String(format: "%.1f", number)
            return "GPU Power \(watts.hasSuffix(".0") ? String(watts.dropLast(2)) : watts)W"
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
#if STEP31_REVIEW
    var reviewOnSample: (([String: Any]) -> Void)?
    private var reviewLastTick = ProcessInfo.processInfo.systemUptime
#endif

    func start() {
        guard !started else { return }
        started = true
        snapshot.metrics["thermal"] = .thermal(ProcessInfo.processInfo.thermalState)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.snapshot.metrics["thermal"] = .thermal(ProcessInfo.processInfo.thermalState)
            self.onUpdate?(self.snapshot)
        }
        onUpdate?(snapshot)
        queue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let collector = TelemetryBackend()
                self.backend = collector
                collector.pressureChanged = { [weak self] in
                    self?.queue.async { [weak self] in
                        guard let self, !self.stopped, let collector = self.backend else { return }
                        autoreleasepool { self.deliver(collector.samplePressure() as NSDictionary) }
                    }
                }
                self.deliver(collector.sampleSlow() as NSDictionary)
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
            if ticks % 3 == 0 { readings.addEntries(from: backend.sampleSlow()) }
            deliver(readings)
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

    private func deliver(_ readings: NSDictionary) {
        let time = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.snapshot.merge(readings, at: time, uptime: uptime)
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
    private let text = NSTextField(labelWithString: "Waiting for telemetry…")
    private let modeButtons = NSStackView()
    var onMode: ((PrimaryMetric) -> Void)?
    var onQuit: (() -> Void)?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 500))
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
        let heading = NSTextField(labelWithString: "Compute Monitor")
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
        let quit = NSButton(title: "Quit", target: self, action: #selector(quitApp))
        quit.bezelStyle = .rounded
        stack.addArrangedSubview(quit)
        preferredContentSize = NSSize(width: 330, height: 500)
        view = root
    }

    @objc private func selectMode(_ button: NSButton) {
        guard let mode = PrimaryMetric(rawValue: button.tag) else { return }
        onMode?(mode)
    }
    @objc private func quitApp() { onQuit?() }

#if STEP31_REVIEW
    func reviewSelect(_ mode: PrimaryMetric) {
        (modeButtons.arrangedSubviews[mode.rawValue] as? NSButton)?.performClick(nil)
    }
#endif

    func update(_ snapshot: TelemetrySnapshot, selected: PrimaryMetric) {
        _ = view
        func line(_ label: String, _ key: String) -> String {
            let value = snapshot[key]?.display ?? "Unavailable"
            return String(format: "%-16@ %@", label as NSString, value)
        }
        let lines = [
            "CPU", line("Total", "total"), line("P-core", "p"), line("E-core", "e"), "",
            "GPU", line("Active", "gpuActive"), line("Weighted freq.", "gpuFrequency"), line("Power", "gpuPower"), "",
            "Memory", line("Physical", "physical"), line("Free", "free"),
            line("Active", "active"), line("Inactive", "inactive"),
            line("Wired", "wired"), line("Compressed", "compressed"),
            line("Pressure", "pressure"), line("Swap used", "swapUsed"),
            line("Swap in", "swapIn"), line("Swap out", "swapOut"), "",
            "Temperature sensors", line("CPU Tp05", "cpuTemperature"),
            line("GPU Tg05", "gpuTemperature"), line("System thermal", "thermal")
        ]
        let rendered = lines.joined(separator: "\n")
        if text.stringValue != rendered { text.stringValue = rendered }
        for case let button as NSButton in modeButtons.arrangedSubviews {
            guard let mode = PrimaryMetric(rawValue: button.tag) else { continue }
            let title = mode == selected ? "✓ \(mode.label)" : mode.label
            if button.title != title { button.title = title }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = TelemetryService()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let content = MonitorPopover()
#if STEP31_REVIEW
    private let review = Step31Review()
#endif
    private var selected = PrimaryMetric(rawValue: UserDefaults.standard.integer(forKey: "primaryMetric")) ?? .cpu

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        if popover.isShown { content.update(snapshot, selected: selected) }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.close() }
        else {
            content.update(service.snapshot, selected: selected)
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func applicationWillTerminate(_ notification: Notification) { service.stop() }

#if STEP3_UI_SMOKE
    private func runUISmoke() {
        let initial = statusItem.button?.title ?? ""
        togglePopover()
        let opened = popover.isShown
        let switched = PrimaryMetric.allCases.allSatisfy { mode in
            content.onMode?(mode)
            return selected == mode && statusItem.button?.title == mode.title(in: service.snapshot)
        }
        let variableWidth = statusItem.length == NSStatusItem.variableLength
        let boundaryFits = ["CPU 100%", "GPU 100%", "Temp 100°C", "GPU Power 99.9W"].allSatisfy { title in
            guard let button = statusItem.button, let font = button.font else { return false }
            button.title = title
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
            return button.bounds.width >= textWidth
        }
        render(service.snapshot)
        togglePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let closed = !self.popover.isShown
            let accessory = NSApp.activationPolicy() == .accessory
            let cpuLive = self.service.snapshot["total"]?.number != nil
            let gpuLive = self.service.snapshot["gpuActive"]?.number != nil
            let passed = opened && switched && variableWidth && boundaryFits && closed && accessory && cpuLive && gpuLive
            print("UI_SMOKE opened=\(opened) switched=\(switched) variable_width=\(variableWidth) boundary_fits=\(boundaryFits) closed=\(closed) accessory=\(accessory) cpu=\(cpuLive) gpu=\(gpuLive) initial=\(initial) result=\(passed ? "PASS" : "FAIL")")
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

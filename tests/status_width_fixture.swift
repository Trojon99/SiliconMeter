// AppKit status-item test using the production title layout (no collector or logger).
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let item = NSStatusBar.system.statusItem(withLength: 1)
let button = item.button!
button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
button.alignment = .left

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
func reading(_ value: Double?, unit: String) -> [String: Any] {
    var raw: [String: Any] = ["status": value == nil ? "unavailable" : "measured", "unit": unit, "source": "width-fixture"]
    if let value { raw["value"] = value }
    return raw
}
func sample(_ mode: PrimaryMetric, _ a: Double?, _ b: Double? = nil) -> TelemetrySnapshot {
    var snapshot = TelemetrySnapshot()
    let readings: [String: Any]
    switch mode {
    case .cpu: readings = ["total": reading(a, unit: "ratio")]
    case .gpu: readings = ["gpuActive": reading(a, unit: "ratio")]
    case .temperature: readings = ["cpuTemperature": reading(a, unit: "°C")]
    case .gpuPower: readings = ["gpuPower": reading(a, unit: "W")]
    case .network:
        readings = ["network_rx_bytes_per_sec": reading(a, unit: "B/s"),
                    "network_tx_bytes_per_sec": reading(b, unit: "B/s")]
    }
    snapshot.merge(readings as NSDictionary, at: Date())
    return snapshot
}
func cases(_ mode: PrimaryMetric) -> [(Double?, Double?)] {
    switch mode {
    case .cpu: return [0,0.09,0.10,0.16,0.99,1].map { ($0,nil) } + [(nil,nil)]
    case .gpu: return [0,0.09,0.10,0.99,1].map { ($0,nil) } + [(nil,nil)]
    case .temperature: return [0,9,61,99,100].map { ($0,nil) } + [(nil,nil)]
    case .gpuPower: return [0,9.9,10,99.9].map { ($0,nil) } + [(nil,nil)]
    case .network:
        return [(0,0),(9,9),(999,999),(1_000,1_000),(999_900,999_900),
                (1_000_000,1_000_000),(99_900_000,9_900_000),
                (999_900_000,999_900_000),(1_000_000_000,1_000_000_000),
                (1_000_000_000_000,1_000_000_000_000),(1_200_000,420_000),
                (nil,nil)]
    }
}
func fieldEnds(_ title: NSAttributedString, fields: [String]) -> (CGFloat, CGFloat) {
    let storage = NSTextStorage(attributedString: title)
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 1000, height: 32))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    let ns = title.string as NSString
    func end(_ text: String, backwards: Bool = false) -> CGFloat {
        let range = ns.range(of: text, options: backwards ? .backwards : [])
        require(range.location != NSNotFound, "field missing from attributed title")
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return manager.boundingRect(forGlyphRange: glyphs, in: container).maxX
    }
    return (end(fields[0]), fields.count == 2 ? end(fields[1], backwards: true) : 0)
}

var widths: [String: [String: Double]] = [:]
var checks = 0
for language in AppLanguage.allCases {
    Localizer.shared.select(language)
    var languageWidths: [String: Double] = [:]
    for mode in PrimaryMetric.allCases {
        let layout = StatusTitleLayout(metric: mode, font: button.font!)
        item.length = layout.length
        var expectedFrame: CGFloat?
        var expectedEnds: (CGFloat, CGFloat)?
        for (a,b) in cases(mode) {
            let snapshot = sample(mode,a,b)
            let title = layout.attributedTitle(in: snapshot)
            button.attributedTitle = title
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            button.layoutSubtreeIfNeeded()
            let frame = button.frame.width
            require(abs(item.length - layout.length) < 0.01, "item length changed on value update")
            require(abs(frame - layout.length) < 0.5, "button frame did not match fixed length")
            if let expectedFrame { require(abs(frame-expectedFrame) < 0.01, "status item frame jumped") }
            else { expectedFrame = frame }
            let ends = fieldEnds(title, fields: mode.statusFields(in: snapshot))
            require(ends.0 <= frame - 6, "first value exceeded status item")
            if mode == .network { require(ends.1 <= frame - 6, "TX value exceeded status item") }
            if let expectedEnds {
                require(abs(ends.0-expectedEnds.0) < 1, "first value slot shifted")
                if mode == .network { require(abs(ends.1-expectedEnds.1) < 1, "TX value slot shifted") }
            } else { expectedEnds = ends }
            checks += 1
        }
        languageWidths[String(describing: mode)] = Double(layout.length)
    }
    widths[language.rawValue] = languageWidths
}
NSStatusBar.system.removeStatusItem(item)
let output: [String: Any] = ["result":"PASS","checks":checks,"widths_pt":widths,
                             "fixed_frame":true,"right_aligned_slots":true]
let bytes = try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
print(String(data: bytes, encoding: .utf8)!)

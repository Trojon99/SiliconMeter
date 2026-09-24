// AppKit status-item test using the production title layout (no collector or logger).
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let item = NSStatusBar.system.statusItem(withLength: 1)
let button = item.button!
let neighbor = NSStatusBar.system.statusItem(withLength: 40)
neighbor.button?.title = "N"
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
    case .cpu: return [0,0.09,0.10,0.16,0.17,0.99,1].map { ($0,nil) } + [(nil,nil)]
    case .gpu: return [0,0.09,0.16,0.99,1].map { ($0,nil) } + [(nil,nil)]
    case .temperature: return [0,9,61,99,100].map { ($0,nil) } + [(nil,nil)]
    case .gpuPower:
        return [0,9.4,14,99.9].map { ($0,nil) } +
            [(nil,nil),(Double.greatestFiniteMagnitude,nil),(-Double.greatestFiniteMagnitude,nil)]
    case .network:
        return [(0,0),(9,9),(999,999),(1_000,1_000),(3_400,56_100),
                (999_900,1_000_000),(999_900,999_900),
                (1_000_000,1_000_000),(99_900_000,999_900_000),
                (999_900_000,999_900_000),(1_000_000_000,1_000_000_000),
                (1_000_000_000_000,1_000_000_000_000),(1_200_000,420_000),
                (nil,nil),(Double.greatestFiniteMagnitude,Double.greatestFiniteMagnitude)]
    }
}
func componentRects(_ title: NSAttributedString, mode: PrimaryMetric, fields: [String]) -> [CGRect] {
    let storage = NSTextStorage(attributedString: title)
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 1000, height: 32))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    let ns = title.string as NSString
    let components = mode == .network
        ? [Localizer.shared.text("NET"), "↓", fields[0], "↑", fields[1]]
        : [mode.statusPrefix, fields[0]]
    var searchStart = 0
    return components.map { text in
        let range = ns.range(of: text, range: NSRange(location: searchStart, length: ns.length-searchStart))
        require(range.location != NSNotFound, "field missing from attributed title")
        searchStart = range.location + range.length
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return manager.boundingRect(forGlyphRange: glyphs, in: container)
    }
}

var widths: [String: [String: Double]] = [:]
var gapRanges: [String: [String: [[Double]]]] = [:]
var slotExamples: [String: [String: [String: Double]]] = [:]
var scalarSlots: [String: [String: Double]] = [:]
var checks = 0
let visualDirectory = URL(fileURLWithPath: ".build/status-visual")
try! FileManager.default.createDirectory(at: visualDirectory, withIntermediateDirectories: true)
for language in AppLanguage.allCases {
    Localizer.shared.select(language)
    var languageWidths: [String: Double] = [:]
    var languageGaps: [String: [[Double]]] = [:]
    var languageSlots: [String: [String: Double]] = [:]
    var languageScalarSlots: [String: Double] = [:]
    for mode in PrimaryMetric.allCases {
        let layout = StatusTitleLayout(metric: mode, font: button.font!)
        item.length = layout.length
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        var expectedFrame: CGFloat?
        var expectedNeighborX: CGFloat?
        var expectedTargetX: CGFloat?
        var expectedScalarStart: CGFloat?
        var expectedScalarGap: CGFloat?
        var endsByShape: [String: [CGFloat]] = [:]
        var range: [[Double]] = []
        for (index, values) in cases(mode).enumerated() {
            let (a,b) = values
            let snapshot = sample(mode,a,b)
            let fields = mode.statusFields(in: snapshot)
            let title = layout.attributedTitle(in: snapshot)
            button.attributedTitle = title
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            button.layoutSubtreeIfNeeded()
            let frame = button.frame.width
            require(abs(item.length - layout.length) < 0.01, "item length changed on value update")
            require(abs(frame - layout.length) < 0.5, "button frame did not match fixed length")
            if let expectedFrame { require(abs(frame-expectedFrame) < 0.01, "status item frame jumped") }
            else { expectedFrame = frame }
            let neighborX = neighbor.button!.window!.convertToScreen(
                neighbor.button!.convert(neighbor.button!.bounds, to: nil)).minX
            let targetX = button.window!.convertToScreen(button.convert(button.bounds, to: nil)).minX
            if let expectedNeighborX, let expectedTargetX {
                require(abs(neighborX-expectedNeighborX) < 0.5,
                    "neighbor changed screen position: \(language.rawValue) \(mode) \(fields) " +
                    "item \(expectedTargetX) -> \(targetX), neighbor \(expectedNeighborX) -> \(neighborX)")
                require(abs((neighborX-targetX)-(expectedNeighborX-expectedTargetX)) < 0.5,
                    "neighbor moved relative to item: \(language.rawValue) \(mode) \(fields) " +
                    "item \(expectedTargetX) -> \(targetX), neighbor \(expectedNeighborX) -> \(neighborX)")
            } else {
                expectedNeighborX = neighborX
                expectedTargetX = targetX
            }
            let rects = componentRects(title, mode: mode, fields: fields)
            require(rects.first!.minX >= 0 && rects.last!.maxX <= frame, "text exceeded status item")
            let gaps = zip(rects, rects.dropFirst()).map { $1.minX - $0.maxX }
            if range.isEmpty { range = gaps.map { [Double($0),Double($0)] } }
            else {
                for (i,gap) in gaps.enumerated() {
                    range[i][0] = min(range[i][0],Double(gap))
                    range[i][1] = max(range[i][1],Double(gap))
                }
            }
            if mode == .network {
                require(gaps[0] >= 4 && gaps[0] <= 8, "NET/arrow gap outside compact range: \(gaps)")
                require(gaps[1] >= 1 && gaps[1] <= 5, "RX arrow/value gap outside compact range: \(gaps)")
                require(gaps[2] >= 5 && gaps[2] <= 9, "RX/TX gap outside compact range: \(gaps)")
                require(gaps[3] >= 1 && gaps[3] <= 5, "TX arrow/value gap outside compact range: \(gaps)")
            } else {
                require(gaps[0] >= 2 && gaps[0] <= 5, "label/value gap outside compact range: \(gaps)")
                if let expectedScalarStart {
                    require(abs(rects[1].minX-expectedScalarStart) < 1, "scalar value start shifted")
                } else { expectedScalarStart = rects[1].minX }
                if let expectedScalarGap {
                    require(abs(gaps[0]-expectedScalarGap) < 1, "scalar label/value gap changed")
                } else { expectedScalarGap = gaps[0] }
            }
            let shape = fields.map { String($0.map { $0 >= "0" && $0 <= "9" ? "8" : $0 }) }.joined(separator: "|")
            let ends = fields.count == 2 ? [rects[2].maxX, rects[4].maxX] : [rects[1].maxX]
            if let previous = endsByShape[shape] {
                require(zip(previous,ends).allSatisfy { abs($0-$1) < 1 }, "same-shape value alignment shifted")
            } else { endsByShape[shape] = ends }
            guard let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) else {
                fatalError("status button bitmap unavailable")
            }
            button.cacheDisplay(in: button.bounds, to: bitmap)
            let name = "\(language.rawValue)-\(String(describing: mode))-\(index).png"
            try! bitmap.representation(using: .png, properties: [:])!
                .write(to: visualDirectory.appendingPathComponent(name))
            checks += 1
        }
        let name = String(describing: mode)
        languageWidths[name] = Double(layout.length)
        languageGaps[name] = range
        if mode != .network { languageScalarSlots[name] = Double(layout.scalarSlotWidth) }
        if mode == .network {
            let templates = ["0 B/s", "3.4 KB/s", "56.1 KB/s", "999.9 KB/s", "999.9 MB/s", "1.0 GB/s", "—"]
            languageSlots[name] = Dictionary(uniqueKeysWithValues: templates.map { ($0,Double(layout.slotWidth(for:$0))) })
        }
    }
    widths[language.rawValue] = languageWidths
    gapRanges[language.rawValue] = languageGaps
    slotExamples[language.rawValue] = languageSlots
    scalarSlots[language.rawValue] = languageScalarSlots
}
NSStatusBar.system.removeStatusItem(item)
NSStatusBar.system.removeStatusItem(neighbor)
let output: [String: Any] = ["result":"PASS","checks":checks,"widths_pt":widths,
                             "gap_ranges_pt":gapRanges,"slot_widths_pt":slotExamples,
                             "fixed_scalar_slot_widths_pt":scalarSlots,
                             "fixed_frame":true,"neighbor_stable":true,"neighbor_relative_stable":true,
                             "compact_component_gaps":true,"same_shape_alignment":true]
let bytes = try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
print(String(data: bytes, encoding: .utf8)!)

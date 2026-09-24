// Contact sheet from real NSStatusBarButton bitmap captures made by status_width_fixture.swift.
import AppKit

let rows: [(String, String, Int)] = [
    ("CPU 9%", "cpu", 1), ("CPU 17%", "cpu", 4), ("CPU 100%", "cpu", 6), ("CPU —", "cpu", 7),
    ("GPU 9%", "gpu", 1), ("GPU 16%", "gpu", 2), ("GPU 100%", "gpu", 4), ("GPU —", "gpu", 5),
    ("Temp 9°C", "temperature", 1), ("Temp 61°C", "temperature", 2),
    ("Temp 100°C", "temperature", 4), ("Temp —", "temperature", 5),
    ("GPU Power 9.4W", "gpuPower", 1), ("GPU Power 14.0W", "gpuPower", 2),
    ("GPU Power 99.9W", "gpuPower", 3), ("GPU Power —", "gpuPower", 4),
    ("NET 0 B/s / 0 B/s", "network", 0), ("NET 3.4 KB/s / 56.1 KB/s", "network", 4),
    ("NET 999.9 KB/s / 1.0 MB/s", "network", 5),
    ("NET 99.9 MB/s / 999.9 MB/s", "network", 8),
    ("NET 1.0 GB/s / 1.0 GB/s", "network", 10), ("NET — / —", "network", 13)
]

let directory = URL(fileURLWithPath: ".build/status-visual")
let output = URL(fileURLWithPath: "docs/results/status-visual.png")
let width = 760
let rowHeight = 30
let height = 54 + rows.count * rowHeight
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("contact sheet bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white
]
let rowAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(calibratedWhite: 0.82, alpha: 1)
]
("AppKit status item captures · English / 简体中文" as NSString).draw(
    at: NSPoint(x: 14, y: height - 25), withAttributes: titleAttributes)
for (index, row) in rows.enumerated() {
    let y = height - 51 - index * rowHeight
    (row.0 as NSString).draw(at: NSPoint(x: 14, y: y + 5), withAttributes: rowAttributes)
    for (language, x) in [("en", 244.0), ("zh-Hans", 498.0)] {
        let url = directory.appendingPathComponent("\(language)-\(row.1)-\(row.2).png")
        guard let image = NSImage(contentsOf: url) else { fatalError("missing \(url.path)") }
        image.draw(in: NSRect(x: x, y: CGFloat(y), width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1)
    }
}
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
try! bitmap.representation(using: .png, properties: [:])!.write(to: output)
print(output.path)

import AppKit
import Foundation

// Drives real AppKit controls from the existing sampling callback. No extra timer,
// collector, observer, hardware read, or in-memory sample history is introduced.
final class Step31Review {
    private let start = ProcessInfo.processInfo.systemUptime
    private var toggles = 0
    private var selections = 0
    private var lastActionSlot = -1

    func observe(_ input: [String: Any], snapshot: TelemetrySnapshot,
                 isShown: () -> Bool, toggle: () -> Void,
                 select: (PrimaryMetric) -> Void, selected: () -> PrimaryMetric,
                 title: () -> String) {
        autoreleasepool {
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            // 30 s warmup + three 600 s phases. Each phase exercises UI twice.
            let phaseTime = max(0, elapsed - 30).truncatingRemainder(dividingBy: 600)
            let slot = Int(elapsed / 2)
            var action = "none"
            let cycling = (120..<180).contains(phaseTime) || (420..<480).contains(phaseTime)
            let heldOpen = (180..<240).contains(phaseTime) || (480..<540).contains(phaseTime)
            if cycling && slot != lastActionSlot {
                toggle(); toggles += 1
                let mode = PrimaryMetric.allCases[selections % 4]
                select(mode); selections += 1
                action = "toggle_and_select"
                lastActionSlot = slot
            } else if isShown() != heldOpen && !cycling {
                toggle(); toggles += 1; action = heldOpen ? "open" : "close"
            }
            var row = input
            row["elapsed_s"] = elapsed
            row["popover_open"] = isShown()
            row["ui_action"] = action
            row["toggle_count"] = toggles
            row["selection_count"] = selections
            row["selected"] = selected().rawValue
            row["title"] = title()
            row["title_matches_snapshot"] = title() == selected().title(in: snapshot)
            row["display"] = snapshot.metrics.mapValues { $0.display }
            do {
                let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data([10]))
            } catch { fputs("Review JSON failure: \(error)\n", stderr); exit(4) }
            if elapsed >= Double(ProcessInfo.processInfo.environment["STEP31_DURATION"] ?? "1832")! {
                NSApp.terminate(nil)
            }
        }
    }
}

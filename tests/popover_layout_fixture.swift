import AppKit

_ = NSApplication.shared
var snapshot = TelemetrySnapshot()
snapshot.merge(["total": ["status": "measured", "value": 1.0, "unit": "ratio"],
                "gpuActive": ["status": "measured", "value": 1.0, "unit": "ratio"],
                "gpuPower": ["status": "estimated", "value": 99.9, "unit": "W"],
                "cpuTemperature": ["status": "measured", "value": 100.0, "unit": "°C"],
                "network_rx_bytes_per_sec": ["status": "measured", "value": 12_400_000.0, "unit": "B/s"],
                "network_tx_bytes_per_sec": ["status": "measured", "value": 420_000.0, "unit": "B/s"]], at: Date())
let popover = MonitorPopover()
for language in AppLanguage.allCases {
    Localizer.shared.select(language)
    popover.update(snapshot, selected: .gpuPower, history: .init(recording: true, sizeBytes: 12_400_000))
    guard popover.smokeLayoutFits() else {
        fputs("POPOVER_LAYOUT FAIL \(language.rawValue)\n", stderr)
        exit(1)
    }
}
print("POPOVER_LAYOUT PASS English/Chinese")

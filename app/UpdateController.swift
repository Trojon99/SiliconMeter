#if ENABLE_APP_UPDATES
import AppKit
import Sparkle

// Sparkle owns version comparison, signed downloads, installation and relaunch.
// Monitoring/history never enter the updater or its network requests.
final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    private var availabilityObservation: NSKeyValueObservation?
    private var automaticObservation: NSKeyValueObservation?
    var onAvailability: ((Bool, Bool) -> Void)?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        availabilityObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            self?.publishAvailability()
        }
        automaticObservation = controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            self?.publishAvailability()
        }
    }

    func start() {
        controller.startUpdater()
        publishAvailability()
    }

    func check() {
        NSApp.activate(ignoringOtherApps: true)
        if controller.updater.canCheckForUpdates { controller.checkForUpdates(nil) }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        publishAvailability()
    }

    private func publishAvailability() {
        onAvailability?(controller.updater.canCheckForUpdates, controller.updater.automaticallyChecksForUpdates)
    }

    // Accessory apps have no Dock icon. Sparkle can show scheduled reminders
    // behind the foreground app; user-initiated checks always take focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }
}
#endif

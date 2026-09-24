import Foundation

// Runs once at launch, before the history writer opens SQLite and before UI
// preferences are loaded. The old directory is moved as a unit so WAL/SHM and
// any other logger files stay alongside the database.
enum IdentityMigration {
    static let legacyBundleID = "local.compute-monitor"
    static let legacyDirectoryName = "Compute Monitor"
    static let directoryName = "SiliconMeter"
    static let languageKey = "appLanguage"
    static let primaryMetricKey = "primaryMetric"

    enum DirectoryResult: Equatable {
        case fresh, moved, existing, conflict, failed
    }

    static func prepareDirectory(in supportDirectory: URL, fileManager: FileManager = .default) -> DirectoryResult {
        let legacy = supportDirectory.appendingPathComponent(legacyDirectoryName, isDirectory: true)
        let current = supportDirectory.appendingPathComponent(directoryName, isDirectory: true)
        var legacyIsDirectory: ObjCBool = false
        var currentIsDirectory: ObjCBool = false
        let legacyExists = fileManager.fileExists(atPath: legacy.path, isDirectory: &legacyIsDirectory)
        let currentExists = fileManager.fileExists(atPath: current.path, isDirectory: &currentIsDirectory)

        if currentExists {
            guard currentIsDirectory.boolValue else {
                NSLog("SiliconMeter history path is not a directory; refusing to open history")
                return .failed
            }
            if legacyExists {
                NSLog("SiliconMeter history migration conflict: both data paths exist; using SiliconMeter and preserving legacy data")
                return .conflict
            }
            return .existing
        }
        guard legacyExists else { return .fresh }
        guard legacyIsDirectory.boolValue else {
            NSLog("SiliconMeter legacy history path is not a directory; refusing to create new history")
            return .failed
        }
        do {
            // Both paths have the same parent. moveItem renames the whole tree
            // without opening or copying an individual SQLite/WAL/SHM file.
            try fileManager.moveItem(at: legacy, to: current)
            NSLog("SiliconMeter legacy history directory migrated")
            return .moved
        } catch {
            NSLog("SiliconMeter history migration failed; refusing to create new history: %@", error.localizedDescription)
            return .failed
        }
    }

    static func migratePreferences(from legacy: UserDefaults, to current: UserDefaults) {
        if current.object(forKey: languageKey) == nil,
           let language = legacy.string(forKey: languageKey),
           language == "en" || language == "zh-Hans" {
            current.set(language, forKey: languageKey)
        }
        if current.object(forKey: primaryMetricKey) == nil,
           let metric = legacy.object(forKey: primaryMetricKey) as? Int,
           (0...4).contains(metric) {
            current.set(metric, forKey: primaryMetricKey)
        }
    }

    static func prepareForLaunch() -> Bool {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard prepareDirectory(in: support) != .failed else { return false }
        if let legacy = UserDefaults(suiteName: legacyBundleID) {
            migratePreferences(from: legacy, to: .standard)
        }
        return true
    }
}

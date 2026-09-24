import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("IDENTITY_MIGRATION_FAIL \(message)\n", stderr); exit(1) }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fm = FileManager.default
let support = root.appendingPathComponent("support", isDirectory: true)
try fm.createDirectory(at: support, withIntermediateDirectories: true)

check(IdentityMigration.prepareDirectory(in: support) == .fresh, "fresh directory state")
check(!fm.fileExists(atPath: support.appendingPathComponent("SiliconMeter").path), "fresh check must not create a directory")

let legacy = support.appendingPathComponent("Compute Monitor", isDirectory: true)
let current = support.appendingPathComponent("SiliconMeter", isDirectory: true)
try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
let marker = legacy.appendingPathComponent("other-logger-metadata")
try Data("preserve".utf8).write(to: marker)
check(IdentityMigration.prepareDirectory(in: support) == .moved, "move legacy directory")
check(!fm.fileExists(atPath: legacy.path), "legacy directory left behind")
check((try? Data(contentsOf: current.appendingPathComponent("other-logger-metadata"))) == Data("preserve".utf8), "other metadata lost")
check(IdentityMigration.prepareDirectory(in: support) == .existing, "repeat move")

try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
try Data("legacy".utf8).write(to: legacy.appendingPathComponent("source"))
try Data("current".utf8).write(to: current.appendingPathComponent("destination"))
check(IdentityMigration.prepareDirectory(in: support) == .conflict, "both directories conflict")
check((try? Data(contentsOf: legacy.appendingPathComponent("source"))) == Data("legacy".utf8), "legacy conflict content changed")
check((try? Data(contentsOf: current.appendingPathComponent("destination"))) == Data("current".utf8), "current conflict content changed")

let bad = root.appendingPathComponent("bad", isDirectory: true)
try fm.createDirectory(at: bad, withIntermediateDirectories: true)
try Data("file".utf8).write(to: bad.appendingPathComponent("Compute Monitor"))
check(IdentityMigration.prepareDirectory(in: bad) == .failed, "non-directory legacy must block new history")

let legacySuite = "identity-test-legacy-\(UUID().uuidString)"
let currentSuite = "identity-test-current-\(UUID().uuidString)"
let old = UserDefaults(suiteName: legacySuite)!
let new = UserDefaults(suiteName: currentSuite)!
defer {
    old.removePersistentDomain(forName: legacySuite)
    new.removePersistentDomain(forName: currentSuite)
}
for language in ["zh-Hans", "en"] {
    old.set(language, forKey: IdentityMigration.languageKey)
    new.removeObject(forKey: IdentityMigration.languageKey)
    IdentityMigration.migratePreferences(from: old, to: new)
    check(new.string(forKey: IdentityMigration.languageKey) == language, "language import \(language)")
    new.set(language == "en" ? "zh-Hans" : "en", forKey: IdentityMigration.languageKey)
    IdentityMigration.migratePreferences(from: old, to: new)
    check(new.string(forKey: IdentityMigration.languageKey) != language, "language overwritten after user change")
}
for metric in 0...4 {
    old.set(metric, forKey: IdentityMigration.primaryMetricKey)
    new.removeObject(forKey: IdentityMigration.primaryMetricKey)
    IdentityMigration.migratePreferences(from: old, to: new)
    check(new.integer(forKey: IdentityMigration.primaryMetricKey) == metric, "primary metric import \(metric)")
    new.set(metric == 1 ? 4 : 1, forKey: IdentityMigration.primaryMetricKey)
    IdentityMigration.migratePreferences(from: old, to: new)
    check(new.integer(forKey: IdentityMigration.primaryMetricKey) != metric, "metric overwritten after user change")
}
old.set(true, forKey: "launchAtLogin")
old.set("debug", forKey: "unrelatedTestFlag")
new.removeObject(forKey: "launchAtLogin")
new.removeObject(forKey: "unrelatedTestFlag")
IdentityMigration.migratePreferences(from: old, to: new)
check(new.object(forKey: "launchAtLogin") == nil && new.object(forKey: "unrelatedTestFlag") == nil, "unlisted keys imported")

print("IDENTITY_MIGRATION_FIXTURE PASS directory/fresh/move/conflict/idempotence/language/all-metrics/allowlist")

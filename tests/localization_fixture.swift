import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("LOCALIZATION FAIL: \(message)\n", stderr); exit(1) }
}

let bundle = Bundle(path: CommandLine.arguments[1])!
let suite = "local.compute-monitor.localization-check.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }

let chineseDefault = Localizer(defaults: defaults, resources: bundle, preferredLanguages: ["zh-Hans-CN", "en"])
check(chineseDefault.language == .simplifiedChinese, "Chinese system default")
check(chineseDefault.text("History") == "历史记录", "Chinese resource")
let englishDefault = Localizer(defaults: defaults, resources: bundle, preferredLanguages: ["fr-FR", "zh-Hans-CN"])
check(englishDefault.language == .english, "first system language determines default")
check(englishDefault.text("History") == "History", "English resource")
let saved = Localizer(defaults: defaults, resources: bundle, preferredLanguages: ["en"])
saved.select(.simplifiedChinese)
check(saved.text("GPU Power") == "GPU 功耗", "immediate Chinese switch")
check(saved.text("Unavailable") == "不可用" && saved.text("estimated") == "估算", "Chinese quality semantics")
check(defaults.string(forKey: Localizer.preferenceKey) == "zh-Hans", "persist Chinese")
let restarted = Localizer(defaults: defaults, resources: bundle, preferredLanguages: ["en"])
check(restarted.language == .simplifiedChinese, "Chinese persists across restart")
restarted.select(.english)
check(restarted.text("GPU Power") == "GPU Power", "immediate English switch")
check(restarted.text("Unavailable") == "Unavailable" && restarted.text("estimated") == "estimated", "English quality semantics")
check(Localizer(defaults: defaults, resources: bundle, preferredLanguages: ["zh-Hans"]).language == .english,
      "English persists across restart")
print("LOCALIZATION_CHECKS PASS defaults/switch/resources/quality/persistence")

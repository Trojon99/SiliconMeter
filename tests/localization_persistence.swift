import Foundation

let bundle = Bundle(path: CommandLine.arguments[1])!
let defaults = UserDefaults(suiteName: CommandLine.arguments[2])!
let mode = CommandLine.arguments[3]
let localizer = Localizer(defaults: defaults, resources: bundle,
                          preferredLanguages: mode == "write-cn" ? ["en"] : ["zh-Hans"])
switch mode {
case "write-cn":
    guard localizer.language == .english else { exit(1) }
    localizer.select(.simplifiedChinese)
case "read-cn-write-en":
    guard localizer.language == .simplifiedChinese, localizer.text("History") == "历史记录" else { exit(2) }
    localizer.select(.english)
case "read-en-clean":
    guard localizer.language == .english, localizer.text("History") == "History" else {
        fputs("restart expected English, saved=\(defaults.string(forKey: Localizer.preferenceKey) ?? "nil"), active=\(localizer.language.rawValue), label=\(localizer.text("History"))\n", stderr)
        exit(3)
    }
    defaults.removePersistentDomain(forName: CommandLine.arguments[2])
default: exit(4)
}
_ = defaults.synchronize()

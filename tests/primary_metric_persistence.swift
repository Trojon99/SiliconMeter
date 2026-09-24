import Foundation

let suite = CommandLine.arguments[1]
let action = CommandLine.arguments[2]
let defaults = UserDefaults(suiteName: suite)!
switch action {
case "write":
    let metric = PrimaryMetric(rawValue: Int(CommandLine.arguments[3])!)!
    PrimaryMetricPreference.save(metric, to: defaults)
    guard defaults.synchronize() else { exit(2) }
case "read":
    let metric = PrimaryMetric(rawValue: Int(CommandLine.arguments[3])!)!
    guard PrimaryMetricPreference.load(from: defaults) == metric else { exit(3) }
case "invalid":
    defaults.set(100, forKey: PrimaryMetricPreference.key)
    guard PrimaryMetricPreference.load(from: defaults) == .cpu else { exit(4) }
case "cleanup":
    defaults.removePersistentDomain(forName: suite)
default: exit(5)
}

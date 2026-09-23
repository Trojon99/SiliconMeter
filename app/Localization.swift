import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}

final class Localizer {
    static let shared = Localizer()
    static let preferenceKey = "appLanguage"

    private let defaults: UserDefaults
    private let resources: Bundle
    private(set) var language: AppLanguage

    init(defaults: UserDefaults = .standard, resources: Bundle = .main,
         preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        self.resources = resources
        if let saved = defaults.string(forKey: Self.preferenceKey), let value = AppLanguage(rawValue: saved) {
            language = value
        } else {
            language = preferredLanguages.first?.lowercased().hasPrefix("zh-hans") == true
                || preferredLanguages.first?.lowercased().hasPrefix("zh-cn") == true
                || preferredLanguages.first?.lowercased().hasPrefix("zh-sg") == true
                ? .simplifiedChinese : .english
        }
    }

    func select(_ newLanguage: AppLanguage) {
        language = newLanguage
        defaults.set(newLanguage.rawValue, forKey: Self.preferenceKey)
    }

    func text(_ key: String) -> String {
        guard let path = resources.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

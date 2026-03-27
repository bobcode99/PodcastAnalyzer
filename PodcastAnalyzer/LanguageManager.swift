import Foundation
import Observation

@Observable
@MainActor
final class LanguageManager {
  static let shared = LanguageManager()

  // Stored property so @Observable can track changes and update the UI instantly
  var appLanguage: String {
    didSet { UserDefaults.standard.set(appLanguage, forKey: "appLanguage") }
  }

  private init() {
    self.appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
  }

  var locale: Locale {
    if appLanguage == "system" {
      // If the device's primary language is one we support, honour it.
      // Otherwise fall back to English so unsupported languages (Japanese,
      // Korean, Hindi, …) don't result in missing strings.
      let primary = Locale.preferredLanguages.first ?? "en"
      let isSupported = Self.supportedLanguageIDs.contains { primary.hasPrefix($0) }
      return isSupported ? .autoupdatingCurrent : Locale(identifier: "en")
    }
    return Locale(identifier: appLanguage)
  }

  /// Language IDs (excluding "system") that have translations in Localizable.xcstrings.
  private static let supportedLanguageIDs: [String] = availableLanguages
    .map(\.id)
    .filter { $0 != "system" }

  struct AppLanguage: Identifiable {
    let id: String
    let displayName: String  // in its own language
  }

  static let availableLanguages: [AppLanguage] = [
    AppLanguage(id: "system", displayName: "System Default"),
    AppLanguage(id: "en", displayName: "English"),
    AppLanguage(id: "zh-Hant", displayName: "繁體中文"),
    AppLanguage(id: "zh-Hans", displayName: "简体中文"),
  ]
}

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
      return .autoupdatingCurrent
    }
    return Locale(identifier: appLanguage)
  }

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

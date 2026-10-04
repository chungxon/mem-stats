import Foundation

enum AppLanguage: String, CaseIterable, Equatable, Identifiable {
  case system
  case english
  case vietnamese
  case simplifiedChinese = "zh-Hans"
  case japanese
  case korean
  case spanish
  case french
  case german

  var id: Self { self }

  /// Native names stay recognizable even when the app language changes.
  var displayName: String {
    switch self {
    case .system:
      return "System"
    case .english:
      return "English"
    case .vietnamese:
      return "Tiếng Việt"
    case .simplifiedChinese:
      return "简体中文"
    case .japanese:
      return "日本語"
    case .korean:
      return "한국어"
    case .spanish:
      return "Español"
    case .french:
      return "Français"
    case .german:
      return "Deutsch"
    }
  }

  var locale: Locale {
    switch self {
    case .system:
      return Locale(identifier: Locale.preferredLanguages.first ?? "en")
    case .english:
      return Locale(identifier: "en")
    case .vietnamese:
      return Locale(identifier: "vi")
    case .simplifiedChinese:
      return Locale(identifier: "zh-Hans")
    case .japanese:
      return Locale(identifier: "ja")
    case .korean:
      return Locale(identifier: "ko")
    case .spanish:
      return Locale(identifier: "es")
    case .french:
      return Locale(identifier: "fr")
    case .german:
      return Locale(identifier: "de")
    }
  }
}

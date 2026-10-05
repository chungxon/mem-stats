import Foundation

enum AppLocalization {
  static func string(_ key: String, language: AppLanguage) -> String {
    String(
      localized: String.LocalizationValue(key),
      bundle: .main,
      locale: language.locale
    )
  }

  static func formatted(
    _ key: String,
    language: AppLanguage,
    _ arguments: CVarArg...
  ) -> String {
    String(
      format: string(key, language: language),
      locale: language.locale,
      arguments: arguments
    )
  }
}

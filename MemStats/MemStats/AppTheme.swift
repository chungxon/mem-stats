import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Equatable, Identifiable {
  case system
  case light
  case dark

  var id: Self { self }

  var displayName: String {
    switch self {
    case .system:
      return "System"
    case .light:
      return "Light"
    case .dark:
      return "Dark"
    }
  }

  /// `nil` removes the app-level override and lets macOS follow its current appearance.
  var nsAppearance: NSAppearance? {
    switch self {
    case .system:
      return nil
    case .light:
      return NSAppearance(named: .aqua)
    case .dark:
      return NSAppearance(named: .darkAqua)
    }
  }

  /// SwiftUI views need the same explicit override while the setting is selected.
  var swiftUIColorScheme: ColorScheme? {
    switch self {
    case .system:
      return nil
    case .light:
      return .light
    case .dark:
      return .dark
    }
  }
}

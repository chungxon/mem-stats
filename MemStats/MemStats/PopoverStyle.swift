import AppKit
import SwiftUI

/// Colors and number text shared by the popover sections.
enum PopoverStyle {
  /// Stable per-user color. Green, orange and red are left out so a user never looks like the
  /// "Free" slice or a pressure level.
  static func userColor(_ user: String) -> Color {
    let palette: [Color] = [.blue, .purple, .mint, .indigo, .teal, .cyan, .pink, .brown]
    return palette[DonutDataBuilder.paletteIndex(for: user, paletteCount: palette.count)]
  }

  static func sliceColor(_ slice: DonutSlice) -> Color {
    switch slice.category {
    case .free:
      return Color.green
    case .others:
      return Color(nsColor: .systemGray)
    case .unattributed:
      return Color(nsColor: unattributedColor)
    case .user(let user):
      return userColor(user)
    }
  }

  static func pressureColor(_ level: MemoryPressureLevel) -> Color {
    Color(nsColor: level.color)
  }

  /// Rounds the same way everywhere, so a slice and the total never disagree by one point.
  static func percentText(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded()))%"
  }

  /// Opaque gray that reads differently from the "Others" slice and keeps at least 3:1 contrast
  /// with the background: darker than system gray in light mode, lighter in dark mode. Resolved
  /// per appearance, since `Color.mix(with:by:)` needs macOS 15. (`tertiaryLabelColor` is
  /// translucent and too faint on a light background.)
  private static let unattributedColor = NSColor(name: nil) { appearance in
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    var color = NSColor.systemGray
    appearance.performAsCurrentDrawingAppearance {
      let base = NSColor.systemGray.usingColorSpace(.sRGB)
      color =
        (isDark
          ? base?.blended(withFraction: 0.45, of: .white)
          : base?.blended(withFraction: 0.35, of: .black)) ?? .systemGray
    }
    return color
  }
}

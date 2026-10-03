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

  /// Opaque lighter gray so it reads differently from the "Others" slice. Resolved per
  /// appearance, since `Color.mix(with:by:)` needs macOS 15.
  private static let unattributedColor = NSColor(name: nil) { appearance in
    var color = NSColor.systemGray
    appearance.performAsCurrentDrawingAppearance {
      color =
        NSColor.systemGray.usingColorSpace(.sRGB)?.blended(withFraction: 0.45, of: .white)
        ?? .systemGray
    }
    return color
  }
}

import AppKit

/// Single source for how a pressure level looks, shared by the menu bar item and the popover.
extension MemoryPressureLevel {
  var displayName: String {
    switch self {
    case .normal:
      return "Normal"
    case .warning:
      return "Warning"
    case .critical:
      return "Critical"
    }
  }

  /// Orange (not yellow) for warning, since yellow is hard to read on a light menu bar.
  var color: NSColor {
    switch self {
    case .normal:
      return .systemGreen
    case .warning:
      return .systemOrange
    case .critical:
      return .systemRed
    }
  }
}

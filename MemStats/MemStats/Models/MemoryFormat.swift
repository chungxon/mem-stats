import Foundation

/// Text for memory sizes in the popover. Binary units, matching Activity Monitor.
nonisolated enum MemoryFormat {
  static let bytesPerMegabyte = 1_048_576.0
  static let bytesPerGigabyte = 1_073_741_824.0

  /// `%.0f MB` below 1 GB, `%.2f GB` from 1 GB.
  static func size(_ bytes: UInt64) -> String {
    let value = Double(bytes)
    // Values that round up to 1024 MB read better as GB.
    if (value / bytesPerMegabyte).rounded() < 1024 {
      return String(format: "%.0f MB", value / bytesPerMegabyte)
    }
    return String(format: "%.2f GB", value / bytesPerGigabyte)
  }

  /// About four ticks from 0 to `upperBound`, on whole gigabytes (1, 2, 4, 8... GB apart) so
  /// labels stay short.
  static func axisTickValues(upperBound: Double) -> [Double] {
    let totalGB = max(0, upperBound) / bytesPerGigabyte
    guard totalGB >= 1 else { return [0] }

    var stepGB = 1.0
    while totalGB / stepGB > 4 {
      stepGB *= 2
    }
    var ticks = Array(stride(from: 0, through: totalGB, by: stepGB))
    // Always end on total RAM (18 or 36 GB Macs are not a multiple of the step), dropping a tick
    // too close to it so labels never overlap.
    if let last = ticks.last, last < totalGB {
      if totalGB - last < stepGB / 2, ticks.count > 1 {
        ticks.removeLast()
      }
      ticks.append(totalGB)
    }
    return ticks.map { $0 * bytesPerGigabyte }
  }

  /// Short label for a history axis tick. Whole gigabytes drop the decimals, and 0 keeps its unit.
  static func axisTick(_ bytes: Double) -> String {
    let gb = max(0, bytes) / bytesPerGigabyte
    if gb.rounded() == gb {
      return String(format: "%.0f GB", gb)
    }
    return String(format: "%.1f GB", gb)
  }
}

import Foundation

/// A per-user hint that memory is growing in a way that may point to a leak. Nonisolated so
/// its `Equatable` conformance works outside the main actor (tests, background work).
nonisolated struct MemoryGrowthHint: Identifiable, Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    /// Memory went up on every one of the last `samples` samples.
    case continuousGrowth(samples: Int)
    /// Memory went up by a large amount between the last two samples.
    case suddenJump
  }

  let user: String
  let kind: Kind
  let growthBytes: UInt64

  /// Unique even if one user ever has two kinds of hint at once.
  var id: String {
    switch kind {
    case .continuousGrowth:
      return "\(user)|growth"
    case .suddenJump:
      return "\(user)|jump"
    }
  }
}

enum MemoryGrowthDetector {
  static let growthSampleCount = 12
  /// Small steady increases are normal, so continuous growth also needs a meaningful total.
  static let minimumContinuousGrowthBytes: UInt64 = 100 * 1024 * 1024
  static let minimumJumpBytes: UInt64 = 500 * 1024 * 1024
  static let jumpFractionOfTotal = 0.05

  /// Checks one user's history (oldest first). A sudden jump wins over continuous growth
  /// because it is the stronger signal.
  static func hint(
    user: String,
    history: [UInt64],
    totalBytes: UInt64,
    growthSampleCount: Int = growthSampleCount
  ) -> MemoryGrowthHint? {
    guard history.count >= 2, let latest = history.last else { return nil }

    let previous = history[history.count - 2]
    let jumpThreshold = max(
      minimumJumpBytes,
      UInt64(Double(totalBytes) * jumpFractionOfTotal)
    )
    if latest > previous, latest - previous > jumpThreshold {
      return MemoryGrowthHint(user: user, kind: .suddenJump, growthBytes: latest - previous)
    }

    guard growthSampleCount >= 2, history.count >= growthSampleCount else { return nil }

    let window = history.suffix(growthSampleCount)
    let isStrictlyIncreasing = zip(window, window.dropFirst()).allSatisfy { $0 < $1 }
    guard let first = window.first, isStrictlyIncreasing else { return nil }

    let growth = latest - first
    guard growth >= minimumContinuousGrowthBytes else { return nil }

    return MemoryGrowthHint(
      user: user,
      kind: .continuousGrowth(samples: growthSampleCount),
      growthBytes: growth
    )
  }
}

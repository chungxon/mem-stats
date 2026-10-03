import Combine
import Foundation

@MainActor
final class MemoryViewModel: ObservableObject {
  @Published private(set) var currentStats: MemoryStats?
  @Published private(set) var history: [MemoryHistorySample] = []

  private(set) var maxSamples: Int

  init(maxSamples: Int = 120) {
    self.maxSamples = max(maxSamples, 1)
  }

  /// Changes how many samples are kept and drops the oldest ones that no longer fit.
  func setMaxSamples(_ maxSamples: Int) {
    self.maxSamples = max(maxSamples, 1)
    if history.count > self.maxSamples {
      history.removeFirst(history.count - self.maxSamples)
    }
  }

  func apply(stats: MemoryStats, sampledAt: Date = Date()) {
    currentStats = stats
    let adjustedTimestamp: Date
    if let lastTimestamp = history.last?.timestamp, sampledAt <= lastTimestamp {
      adjustedTimestamp = lastTimestamp.addingTimeInterval(0.001)
    } else {
      adjustedTimestamp = sampledAt
    }

    history.append(
      MemoryHistorySample(
        timestamp: adjustedTimestamp,
        usedBytes: stats.usedBytes,
        swapUsedBytes: stats.swapUsedBytes,
        pressureLevel: stats.pressureLevel
      )
    )

    if history.count > maxSamples {
      history.removeFirst(history.count - maxSamples)
    }
  }
}

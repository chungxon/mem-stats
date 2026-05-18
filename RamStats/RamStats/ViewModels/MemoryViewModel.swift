import Combine
import Foundation

@MainActor
final class MemoryViewModel: ObservableObject {
  @Published private(set) var currentStats: MemoryStats?
  @Published private(set) var history: [MemoryHistorySample] = []

  private let maxSamples: Int

  init(maxSamples: Int = 120) {
    self.maxSamples = max(maxSamples, 1)
  }

  func apply(stats: MemoryStats, sampledAt: Date = Date()) {
    currentStats = stats

    history.append(
      MemoryHistorySample(
        timestamp: sampledAt,
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

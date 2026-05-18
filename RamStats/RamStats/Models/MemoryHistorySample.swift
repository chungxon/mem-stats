import Foundation

struct MemoryHistorySample: Sendable, Equatable {
  let timestamp: Date
  let usedBytes: UInt64
  let swapUsedBytes: UInt64
  let pressureLevel: MemoryPressureLevel
}

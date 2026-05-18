import Foundation

enum MemoryPressureLevel: String, Sendable {
  case normal
  case warning
  case critical
}

struct MemoryStats: Sendable {
  let totalBytes: UInt64
  let usedBytes: UInt64
  let freeBytes: UInt64
  let activeBytes: UInt64
  let inactiveBytes: UInt64
  let wiredBytes: UInt64
  let compressedBytes: UInt64
  let swapUsedBytes: UInt64
  let pressureLevel: MemoryPressureLevel
}

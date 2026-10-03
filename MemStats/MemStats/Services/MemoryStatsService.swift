import Darwin
import Foundation

protocol MemoryStatsProviding: Sendable {
  nonisolated func fetchMemoryStats() throws -> MemoryStats
}

enum MemoryStatsServiceError: Error {
  case hostPageSizeFailed
  case hostStatisticsFailed(kern_return_t)
  case totalRAMUnavailable
  case swapUsageUnavailable
}

extension MemoryStatsServiceError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .hostPageSizeFailed:
      return "Could not read system page size."
    case .hostStatisticsFailed(let code):
      return "Could not read VM statistics (kern_return_t=\(code))."
    case .totalRAMUnavailable:
      return "Could not read total RAM."
    case .swapUsageUnavailable:
      return "Could not read swap usage."
    }
  }
}

struct MemoryStatsService: MemoryStatsProviding {
  nonisolated func fetchMemoryStats() throws -> MemoryStats {
    let totalBytes = try totalRAMBytes()
    let pageSize = try hostPageSize()
    let vmStats = try vmStatistics()

    let activeBytes = UInt64(vmStats.active_count) * pageSize
    let inactiveBytes = UInt64(vmStats.inactive_count) * pageSize
    let wiredBytes = UInt64(vmStats.wire_count) * pageSize
    let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
    let usedBytes = Self.usedMemoryBytes(
      internalPages: UInt64(vmStats.internal_page_count),
      purgeablePages: UInt64(vmStats.purgeable_count),
      wiredPages: UInt64(vmStats.wire_count),
      compressedPages: UInt64(vmStats.compressor_page_count),
      pageSize: pageSize,
      totalBytes: totalBytes
    )
    // Cached and reclaimable pages count as available, matching Activity Monitor.
    let freeBytes = totalBytes - usedBytes
    let swapUsedBytes = (try? swapUsedBytes()) ?? 0
    let pressureLevel = derivePressureLevel(usedBytes: usedBytes, totalBytes: totalBytes)

    return MemoryStats(
      totalBytes: totalBytes,
      usedBytes: usedBytes,
      freeBytes: freeBytes,
      activeBytes: activeBytes,
      inactiveBytes: inactiveBytes,
      wiredBytes: wiredBytes,
      compressedBytes: compressedBytes,
      swapUsedBytes: swapUsedBytes,
      pressureLevel: pressureLevel
    )
  }

  /// Activity Monitor style "Memory Used": App Memory (anonymous pages minus purgeable)
  /// + Wired + Compressed. File cache and free pages are treated as available.
  nonisolated static func usedMemoryBytes(
    internalPages: UInt64,
    purgeablePages: UInt64,
    wiredPages: UInt64,
    compressedPages: UInt64,
    pageSize: UInt64,
    totalBytes: UInt64
  ) -> UInt64 {
    let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
    let usedPages = appPages + wiredPages + compressedPages
    let (usedBytes, overflow) = usedPages.multipliedReportingOverflow(by: pageSize)
    guard !overflow else { return totalBytes }
    return min(usedBytes, totalBytes)
  }

  nonisolated private func hostPageSize() throws -> UInt64 {
    var pageSize: vm_size_t = 0
    let result = host_page_size(mach_host_self(), &pageSize)
    guard result == KERN_SUCCESS else {
      throw MemoryStatsServiceError.hostPageSizeFailed
    }

    return UInt64(pageSize)
  }

  nonisolated private func vmStatistics() throws -> vm_statistics64 {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
    )

    let result: kern_return_t = withUnsafeMutablePointer(to: &stats) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
        host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
      }
    }

    guard result == KERN_SUCCESS else {
      throw MemoryStatsServiceError.hostStatisticsFailed(result)
    }

    return stats
  }

  nonisolated private func totalRAMBytes() throws -> UInt64 {
    var total: UInt64 = 0
    var size = MemoryLayout<UInt64>.size

    let result = sysctlbyname("hw.memsize", &total, &size, nil, 0)
    guard result == 0, total > 0 else {
      throw MemoryStatsServiceError.totalRAMUnavailable
    }

    return total
  }

  nonisolated private func swapUsedBytes() throws -> UInt64 {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size

    let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
    guard result == 0 else {
      throw MemoryStatsServiceError.swapUsageUnavailable
    }

    return usage.xsu_used
  }

  nonisolated private func derivePressureLevel(usedBytes: UInt64, totalBytes: UInt64)
    -> MemoryPressureLevel
  {
    if let systemPressureLevel = readSystemPressureLevel() {
      return systemPressureLevel
    }

    guard totalBytes > 0 else { return .normal }

    let ratio = Double(usedBytes) / Double(totalBytes)
    if ratio >= 0.9 {
      return .critical
    }
    if ratio >= 0.75 {
      return .warning
    }

    return .normal
  }

  nonisolated private func readSystemPressureLevel() -> MemoryPressureLevel? {
    let vmPressure = readInt32Sysctl(name: "vm.memory_pressure").map(Self.levelFromVMMemoryPressure)
    let memorystatusPressure = readInt32Sysctl(name: "kern.memorystatus_vm_pressure_level").map(
      Self.levelFromMemorystatusPressure
    )

    switch (vmPressure, memorystatusPressure) {
    case (.some(let lhs), .some(let rhs)):
      return Self.maxPressureLevel(lhs, rhs)
    case (.some(let level), .none), (.none, .some(let level)):
      return level
    case (.none, .none):
      return nil
    }
  }

  nonisolated private func readInt32Sysctl(name: String) -> Int32? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let result = sysctlbyname(name, &value, &size, nil, 0)
    guard result == 0, size == MemoryLayout<Int32>.size else { return nil }
    return value
  }

  nonisolated static func levelFromVMMemoryPressure(_ value: Int32) -> MemoryPressureLevel {
    if value >= 2 {
      return .critical
    }
    if value >= 1 {
      return .warning
    }
    return .normal
  }

  nonisolated static func levelFromMemorystatusPressure(_ value: Int32) -> MemoryPressureLevel {
    if value >= 4 {
      return .critical
    }
    if value >= 2 {
      return .warning
    }
    return .normal
  }

  nonisolated static func maxPressureLevel(_ lhs: MemoryPressureLevel, _ rhs: MemoryPressureLevel)
    -> MemoryPressureLevel
  {
    let lhsRank = pressureRank(lhs)
    let rhsRank = pressureRank(rhs)
    return lhsRank >= rhsRank ? lhs : rhs
  }

  nonisolated private static func pressureRank(_ level: MemoryPressureLevel) -> Int {
    switch level {
    case .normal:
      return 0
    case .warning:
      return 1
    case .critical:
      return 2
    }
  }
}

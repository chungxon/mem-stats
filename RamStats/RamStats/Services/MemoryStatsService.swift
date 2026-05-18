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

struct MemoryStatsService: MemoryStatsProviding {
  nonisolated func fetchMemoryStats() throws -> MemoryStats {
    let totalBytes = try totalRAMBytes()
    let pageSize = try hostPageSize()
    let vmStats = try vmStatistics()

    let freeBytes = UInt64(vmStats.free_count) * pageSize
    let activeBytes = UInt64(vmStats.active_count) * pageSize
    let inactiveBytes = UInt64(vmStats.inactive_count) * pageSize
    let wiredBytes = UInt64(vmStats.wire_count) * pageSize
    let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
    let usedBytes = min(totalBytes, totalBytes &- freeBytes)
    let swapUsedBytes = try swapUsedBytes()
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

  private func hostPageSize() throws -> UInt64 {
    var pageSize: vm_size_t = 0
    let result = host_page_size(mach_host_self(), &pageSize)
    guard result == KERN_SUCCESS else {
      throw MemoryStatsServiceError.hostPageSizeFailed
    }

    return UInt64(pageSize)
  }

  private func vmStatistics() throws -> vm_statistics64 {
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

  private func totalRAMBytes() throws -> UInt64 {
    var total: UInt64 = 0
    var size = MemoryLayout<UInt64>.size

    let result = sysctlbyname("hw.memsize", &total, &size, nil, 0)
    guard result == 0, total > 0 else {
      throw MemoryStatsServiceError.totalRAMUnavailable
    }

    return total
  }

  private func swapUsedBytes() throws -> UInt64 {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size

    let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
    guard result == 0 else {
      throw MemoryStatsServiceError.swapUsageUnavailable
    }

    return usage.xsu_used
  }

  private func derivePressureLevel(usedBytes: UInt64, totalBytes: UInt64) -> MemoryPressureLevel {
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
}

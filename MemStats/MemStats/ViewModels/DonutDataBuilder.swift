import Foundation

struct DonutDataBuilder {
  static func buildSlices(
    totalBytes: UInt64,
    freeBytes: UInt64,
    snapshots: [ProcessSnapshot],
    tinyThreshold: Double = 0.02
  ) -> [DonutSlice] {
    guard totalBytes > 0 else { return [] }

    let cappedFreeBytes = min(freeBytes, totalBytes)
    let targetUsedBytes = totalBytes - cappedFreeBytes

    var perUserBytes: [String: UInt64] = [:]
    for process in snapshots {
      perUserBytes[process.user, default: 0] += process.rssBytes
    }

    let normalizedPerUserBytes = normalizePerUserBytes(
      perUserBytes,
      targetUsedBytes: targetUsedBytes
    )

    let userSlices =
      normalizedPerUserBytes
      .map { user, bytes in
        DonutSlice(
          id: "user:\(user)",
          label: user,
          category: .user(user),
          bytes: bytes,
          fractionOfTotal: Double(bytes) / Double(totalBytes)
        )
      }
      .sorted { lhs, rhs in
        if lhs.bytes == rhs.bytes {
          return lhs.label < rhs.label
        }
        return lhs.bytes > rhs.bytes
      }

    var stableUserSlices: [DonutSlice] = []
    var othersBytes: UInt64 = 0

    for slice in userSlices {
      if slice.fractionOfTotal < tinyThreshold {
        othersBytes += slice.bytes
      } else {
        stableUserSlices.append(slice)
      }
    }

    if othersBytes > 0 {
      stableUserSlices.append(
        DonutSlice(
          id: "others",
          label: "Others",
          category: .others,
          bytes: othersBytes,
          fractionOfTotal: Double(othersBytes) / Double(totalBytes)
        )
      )
    }

    let accountedUsedBytes = stableUserSlices.reduce(UInt64(0)) { $0 + $1.bytes }
    if targetUsedBytes > accountedUsedBytes {
      let unattributedBytes = targetUsedBytes - accountedUsedBytes
      stableUserSlices.append(
        DonutSlice(
          id: "unattributed",
          label: "Unattributed Used",
          category: .unattributed,
          bytes: unattributedBytes,
          fractionOfTotal: Double(unattributedBytes) / Double(totalBytes)
        )
      )
    }

    stableUserSlices.append(
      DonutSlice(
        id: "free",
        label: "Free",
        category: .free,
        bytes: cappedFreeBytes,
        fractionOfTotal: Double(cappedFreeBytes) / Double(totalBytes)
      )
    )

    return stableUserSlices
  }

  private static func normalizePerUserBytes(
    _ perUserBytes: [String: UInt64],
    targetUsedBytes: UInt64
  ) -> [String: UInt64] {
    let totalMeasuredBytes = perUserBytes.values.reduce(UInt64(0), +)
    guard totalMeasuredBytes > 0, targetUsedBytes > 0 else {
      return [:]
    }

    if totalMeasuredBytes <= targetUsedBytes {
      return perUserBytes
    }

    let scale = Double(targetUsedBytes) / Double(totalMeasuredBytes)
    var normalized: [String: UInt64] = [:]
    var totalNormalized: UInt64 = 0

    for (user, bytes) in perUserBytes {
      let scaled = UInt64((Double(bytes) * scale).rounded(.down))
      normalized[user] = scaled
      totalNormalized += scaled
    }

    var remainder = targetUsedBytes - totalNormalized
    if remainder > 0 {
      let sortedUsers = perUserBytes.keys.sorted {
        let lhsBytes = normalized[$0, default: 0]
        let rhsBytes = normalized[$1, default: 0]
        if lhsBytes == rhsBytes {
          return $0 < $1
        }
        return lhsBytes > rhsBytes
      }

      var index = 0
      while remainder > 0, !sortedUsers.isEmpty {
        let user = sortedUsers[index % sortedUsers.count]
        normalized[user, default: 0] += 1
        remainder -= 1
        index += 1
      }
    }

    return normalized.filter { $0.value > 0 }
  }

  static func sliceForSelection(angleValue: Double?, in slices: [DonutSlice]) -> DonutSlice? {
    guard let angleValue else { return nil }

    var cumulative: Double = 0
    for slice in slices {
      cumulative += slice.angleValue
      if angleValue <= cumulative {
        return slice
      }
    }

    return slices.last
  }
}

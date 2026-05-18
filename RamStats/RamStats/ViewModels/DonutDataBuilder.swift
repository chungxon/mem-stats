import Foundation

struct DonutDataBuilder {
  static func buildSlices(
    totalBytes: UInt64,
    freeBytes: UInt64,
    snapshots: [ProcessSnapshot],
    tinyThreshold: Double = 0.02
  ) -> [DonutSlice] {
    guard totalBytes > 0 else { return [] }

    var perUserBytes: [String: UInt64] = [:]
    for process in snapshots {
      perUserBytes[process.user, default: 0] += process.rssBytes
    }

    var userSlices =
      perUserBytes
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

    let cappedFreeBytes = min(freeBytes, totalBytes)
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

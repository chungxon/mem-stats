import Foundation

struct MemoryHistorySample: Sendable, Equatable {
  let timestamp: Date
  let usedBytes: UInt64
  let swapUsedBytes: UInt64
  let pressureLevel: MemoryPressureLevel
}

/// One endpoint of a history line segment. Each pair of adjacent samples becomes its own
/// chart series, so every segment can be colored by pressure without Swift Charts joining
/// non-adjacent samples that happen to share a color.
struct MemoryHistorySegmentPoint: Identifiable, Sendable, Equatable {
  let segmentID: String
  let timestamp: Date
  let usedBytes: UInt64
  /// Pressure of the segment's end sample, so a segment shows the level it leads into.
  let pressureLevel: MemoryPressureLevel

  var id: String {
    "\(segmentID)|\(timestamp.timeIntervalSince1970)"
  }

  static func segments(from samples: [MemoryHistorySample]) -> [MemoryHistorySegmentPoint] {
    guard samples.count > 1 else { return [] }

    var points: [MemoryHistorySegmentPoint] = []
    points.reserveCapacity((samples.count - 1) * 2)

    for index in 1..<samples.count {
      let start = samples[index - 1]
      let end = samples[index]
      let segmentID = "segment-\(start.timestamp.timeIntervalSince1970)"

      for sample in [start, end] {
        points.append(
          MemoryHistorySegmentPoint(
            segmentID: segmentID,
            timestamp: sample.timestamp,
            usedBytes: sample.usedBytes,
            pressureLevel: end.pressureLevel
          )
        )
      }
    }

    return points
  }
}

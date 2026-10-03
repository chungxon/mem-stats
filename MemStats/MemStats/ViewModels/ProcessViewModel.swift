import Combine
import Foundation

@MainActor
final class ProcessViewModel: ObservableObject {
  struct UserMemoryHistorySample: Sendable, Equatable {
    let timestamp: Date
    let user: String
    let rssBytes: UInt64
  }

  @Published private(set) var allProcesses: [ProcessSnapshot] = []
  @Published private(set) var topProcesses: [ProcessSnapshot] = []
  @Published var selectedUser: String?

  private var userHistoryByUser: [String: [UserMemoryHistorySample]] = [:]
  private let maxSamples: Int
  private var topLimit: Int = 8

  init(maxSamples: Int = 120) {
    self.maxSamples = max(maxSamples, 1)
  }

  func apply(snapshots: [ProcessSnapshot], topLimit: Int = 8, sampledAt: Date = Date()) {
    self.topLimit = max(topLimit, 0)
    allProcesses = snapshots
    topProcesses = Array(snapshots.prefix(self.topLimit))
    let adjustedTimestamp: Date
    let latestTimestamp = userHistoryByUser.values.compactMap(\.last?.timestamp).max()
    if let latestTimestamp, sampledAt <= latestTimestamp {
      adjustedTimestamp = latestTimestamp.addingTimeInterval(0.001)
    } else {
      adjustedTimestamp = sampledAt
    }

    var rssByUser: [String: UInt64] = [:]
    for snapshot in snapshots {
      rssByUser[snapshot.user, default: 0] += snapshot.rssBytes
    }

    for (user, rssBytes) in rssByUser {
      var history = userHistoryByUser[user, default: []]
      history.append(
        UserMemoryHistorySample(timestamp: adjustedTimestamp, user: user, rssBytes: rssBytes)
      )
      if history.count > maxSamples {
        history.removeFirst(history.count - maxSamples)
      }
      userHistoryByUser[user] = history
    }

    if let selectedUser, !allProcesses.contains(where: { $0.user == selectedUser }) {
      self.selectedUser = nil
    }
  }

  var visibleProcesses: [ProcessSnapshot] {
    guard let selectedUser else { return topProcesses }
    return Array(allProcesses.filter { $0.user == selectedUser }.prefix(topLimit))
  }

  var selectedUserHistory: [UserMemoryHistorySample] {
    guard let selectedUser else { return [] }
    return userHistoryByUser[selectedUser] ?? []
  }
}

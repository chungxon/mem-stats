import Combine
import Foundation

@MainActor
final class ProcessViewModel: ObservableObject {
  struct UserMemoryHistorySample: Sendable, Equatable {
    let timestamp: Date
    let user: String
    /// Raw summed RSS, used for growth detection.
    let rssBytes: UInt64
    /// RSS scaled the same way as the donut, so it fits on the used RAM chart.
    let displayBytes: UInt64
  }

  @Published private(set) var allProcesses: [ProcessSnapshot] = []
  @Published private(set) var topProcesses: [ProcessSnapshot] = []
  @Published private(set) var visibleApps: [AppMemoryUsage] = []
  @Published var selectedUser: String? {
    didSet {
      guard selectedUser != oldValue else { return }
      refreshVisibleApps()
    }
  }

  private var userHistoryByUser: [String: [UserMemoryHistorySample]] = [:]
  private(set) var maxSamples: Int
  private(set) var topAppsLimit: Int
  private(set) var topProcessesLimit: Int
  private var appIdentities: [Int32: AppIdentity] = [:]

  init(maxSamples: Int = 120, topAppsLimit: Int = 8, topProcessesLimit: Int = 8) {
    self.maxSamples = max(maxSamples, 1)
    self.topAppsLimit = max(topAppsLimit, 0)
    self.topProcessesLimit = max(topProcessesLimit, 0)
  }

  /// Changes the row counts and re-slices the current snapshot, without a new sample.
  func setLimits(topApps: Int, topProcesses: Int) {
    let nextAppsLimit = max(topApps, 0)
    let nextProcessesLimit = max(topProcesses, 0)
    guard nextAppsLimit != topAppsLimit || nextProcessesLimit != topProcessesLimit else { return }

    topAppsLimit = nextAppsLimit
    topProcessesLimit = nextProcessesLimit
    self.topProcesses = Array(allProcesses.prefix(topProcessesLimit))
    refreshVisibleApps()
  }

  /// Changes how many samples each user's history keeps and drops the oldest extra ones.
  func setMaxSamples(_ maxSamples: Int) {
    self.maxSamples = max(maxSamples, 1)
    userHistoryByUser = userHistoryByUser.mapValues { Array($0.suffix(self.maxSamples)) }
  }

  func apply(
    snapshots: [ProcessSnapshot],
    appIdentities: [Int32: AppIdentity] = [:],
    targetUsedBytes: UInt64? = nil,
    sampledAt: Date = Date()
  ) {
    self.appIdentities = appIdentities
    allProcesses = snapshots
    topProcesses = Array(snapshots.prefix(topProcessesLimit))
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

    // Drop history for users missing from this snapshot, so a user that comes back starts a
    // fresh series instead of bridging the gap (which would look like a sudden jump).
    userHistoryByUser = userHistoryByUser.filter { rssByUser[$0.key] != nil }

    let displayByUser = targetUsedBytes.map {
      DonutDataBuilder.normalizePerUserBytes(rssByUser, targetUsedBytes: $0)
    }

    for (user, rssBytes) in rssByUser {
      var history = userHistoryByUser[user, default: []]
      history.append(
        UserMemoryHistorySample(
          timestamp: adjustedTimestamp,
          user: user,
          rssBytes: rssBytes,
          displayBytes: displayByUser.map { $0[user] ?? 0 } ?? rssBytes
        )
      )
      if history.count > maxSamples {
        history.removeFirst(history.count - maxSamples)
      }
      userHistoryByUser[user] = history
    }

    if let selectedUser, !allProcesses.contains(where: { $0.user == selectedUser }) {
      self.selectedUser = nil
    } else {
      refreshVisibleApps()
    }
  }

  var visibleProcesses: [ProcessSnapshot] {
    guard let selectedUser else { return topProcesses }
    return Array(allProcesses.filter { $0.user == selectedUser }.prefix(topProcessesLimit))
  }

  private func refreshVisibleApps() {
    let scopedProcesses: [ProcessSnapshot]
    if let selectedUser {
      scopedProcesses = allProcesses.filter { $0.user == selectedUser }
    } else {
      scopedProcesses = allProcesses
    }

    visibleApps = AppMemoryAggregator.aggregate(
      processes: scopedProcesses,
      identities: appIdentities,
      limit: topAppsLimit
    )
  }

  var selectedUserHistory: [UserMemoryHistorySample] {
    guard let selectedUser else { return [] }
    return userHistoryByUser[selectedUser] ?? []
  }

  func history(for user: String) -> [UserMemoryHistorySample] {
    userHistoryByUser[user] ?? []
  }
}

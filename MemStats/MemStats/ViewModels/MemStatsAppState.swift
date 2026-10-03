import Combine
import Foundation

@MainActor
final class MemStatsAppState: ObservableObject {
  enum SamplingMode: Equatable {
    case active
    case idle
  }

  @Published private(set) var samplingMode: SamplingMode = .idle
  @Published private(set) var lastSamplingError: String?
  @Published private(set) var donutSlices: [DonutSlice] = []
  @Published private(set) var growthHints: [MemoryGrowthHint] = []
  /// Whether `root` and `_*` system users are included in the sampled processes.
  @Published private(set) var showsSystemUsers: Bool

  let memoryVM: MemoryViewModel
  let processVM: ProcessViewModel

  static let showsSystemUsersKey = "showSystemUsers"

  private let memoryService: MemoryStatsService
  private let processService: ProcessSnapshotService
  private let defaults: UserDefaults
  private let samplingQueue = DispatchQueue(label: "com.chungxon.memstats.sampling", qos: .utility)

  private var timer: DispatchSourceTimer?
  private var lastSampleAt: Date?

  init(startSampling: Bool = true, defaults: UserDefaults = .standard) {
    memoryVM = MemoryViewModel()
    processVM = ProcessViewModel()
    memoryService = MemoryStatsService()
    processService = ProcessSnapshotService()
    self.defaults = defaults
    // Shown by default to match Activity Monitor's all-users view.
    showsSystemUsers = defaults.object(forKey: Self.showsSystemUsersKey) as? Bool ?? true

    if startSampling {
      restartSamplingTimer()
    }
  }

  func setShowsSystemUsers(_ shows: Bool) {
    guard shows != showsSystemUsers else { return }

    showsSystemUsers = shows
    defaults.set(shows, forKey: Self.showsSystemUsersKey)
    // Resample right away so every section reflects the new filter.
    if timer != nil {
      sampleImmediately()
    }
  }

  deinit {
    timer?.cancel()
  }

  func setPopoverPresented(_ isPresented: Bool) {
    let nextMode: SamplingMode = isPresented ? .active : .idle
    guard nextMode != samplingMode else { return }

    samplingMode = nextMode
    restartSamplingTimer()
  }

  func sampleImmediately() {
    performSample()
    // Push the next scheduled tick a full interval out so it does not run right after this one.
    restartSamplingTimer()
  }

  func samplingInterval(for mode: SamplingMode) -> TimeInterval {
    switch mode {
    case .active:
      return 5
    case .idle:
      return 15
    }
  }

  /// Delay before the first sample after the timer restarts. Opening and closing the popover
  /// restarts the timer, so a sample taken moments ago is reused instead of spawning `top`
  /// again right away.
  nonisolated static func initialSamplingDelay(
    lastSampleAt: Date?,
    now: Date,
    interval: TimeInterval,
    minimumGap: TimeInterval = 2
  ) -> TimeInterval {
    guard let lastSampleAt else { return 0 }

    let elapsed = now.timeIntervalSince(lastSampleAt)
    guard elapsed >= 0, elapsed < minimumGap else { return 0 }
    return max(0, interval - elapsed)
  }

  private func restartSamplingTimer() {
    timer?.cancel()

    let interval = samplingInterval(for: samplingMode)
    let delay = Self.initialSamplingDelay(
      lastSampleAt: lastSampleAt,
      now: Date(),
      interval: interval
    )
    let nextTimer = DispatchSource.makeTimerSource(queue: samplingQueue)
    nextTimer.schedule(
      deadline: .now() + delay,
      repeating: interval
    )
    nextTimer.setEventHandler { [weak self] in
      Task { @MainActor [weak self] in
        self?.performSample()
      }
    }

    timer = nextTimer
    nextTimer.resume()
  }

  private func performSample() {
    lastSampleAt = Date()
    let memoryService = memoryService
    let processService = processService
    let includesSystemUsers = showsSystemUsers

    samplingQueue.async { [weak self] in
      guard self != nil else { return }
      let sampledAt = Date()
      var messages: [String] = []
      var sampledMemoryStats: MemoryStats?
      var sampledProcesses: [ProcessSnapshot] = []
      var sampledAppIdentities: [Int32: AppIdentity] = [:]
      var didSampleProcesses = false

      let memoryResult = Result { try memoryService.fetchMemoryStats() }
      switch memoryResult {
      case .success(let stats):
        sampledMemoryStats = stats
      case .failure(let error):
        let message = "Memory: \(error.localizedDescription)"
        messages.append(message)
      }

      let processResult = Result {
        try processService.fetchProcesses(
          includeRootUser: includesSystemUsers,
          includeSystemUsers: includesSystemUsers
        )
      }
      switch processResult {
      case .success(let processes):
        sampledProcesses = processes
        sampledAppIdentities = AppIdentityResolver.resolve(pids: processes.map(\.pid))
        didSampleProcesses = true
      case .failure(let error):
        let message = "Process: \(error.localizedDescription)"
        messages.append(message)
      }

      let sampledError = messages.isEmpty ? nil : messages.joined(separator: " | ")
      let finalizedMemoryStats = sampledMemoryStats
      let finalizedProcesses = sampledProcesses
      let finalizedAppIdentities = sampledAppIdentities
      let finalizedDidSampleProcesses = didSampleProcesses
      let finalizedError = sampledError
      let finalizedSampledAt = sampledAt
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.applySample(
          stats: finalizedMemoryStats,
          processes: finalizedDidSampleProcesses ? finalizedProcesses : nil,
          appIdentities: finalizedAppIdentities,
          sampledAt: finalizedSampledAt
        )
        self.lastSamplingError = finalizedError
      }
    }
  }

  /// Applies one sampling result. A `nil` value means that part of the sample failed and the
  /// previous data is kept.
  func applySample(
    stats: MemoryStats?,
    processes: [ProcessSnapshot]?,
    appIdentities: [Int32: AppIdentity] = [:],
    sampledAt: Date = Date()
  ) {
    if let stats {
      memoryVM.apply(stats: stats, sampledAt: sampledAt)
    }
    if let processes {
      processVM.apply(
        snapshots: processes,
        appIdentities: appIdentities,
        topLimit: 8,
        sampledAt: sampledAt
      )
      refreshGrowthHints()
    }
    refreshDonutSlices()
  }

  /// Only users in the current snapshot are checked, so a user that disappeared does not
  /// keep a stale hint.
  private func refreshGrowthHints() {
    guard let totalBytes = memoryVM.currentStats?.totalBytes else {
      if !growthHints.isEmpty {
        growthHints = []
      }
      return
    }

    let currentUsers = Set(processVM.allProcesses.map(\.user))
    let nextHints =
      currentUsers
      .compactMap { user in
        MemoryGrowthDetector.hint(
          user: user,
          history: processVM.history(for: user).map(\.rssBytes),
          totalBytes: totalBytes
        )
      }
      .sorted { lhs, rhs in
        if lhs.growthBytes == rhs.growthBytes {
          return lhs.user < rhs.user
        }
        return lhs.growthBytes > rhs.growthBytes
      }

    if nextHints != growthHints {
      growthHints = nextHints
    }
  }

  /// Donut grouping walks the whole process snapshot, so it runs once per sample here
  /// instead of on every view update (hover fires many updates per second).
  private func refreshDonutSlices() {
    guard let stats = memoryVM.currentStats else {
      if !donutSlices.isEmpty {
        donutSlices = []
      }
      return
    }

    let nextSlices = DonutDataBuilder.buildSlices(
      totalBytes: stats.totalBytes,
      freeBytes: stats.freeBytes,
      snapshots: processVM.allProcesses,
      tinyThreshold: 0.02
    )
    if nextSlices != donutSlices {
      donutSlices = nextSlices
    }
  }
}

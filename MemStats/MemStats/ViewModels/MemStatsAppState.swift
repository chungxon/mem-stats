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

  let memoryVM: MemoryViewModel
  let processVM: ProcessViewModel

  private let memoryService: MemoryStatsService
  private let processService: ProcessSnapshotService
  private let samplingQueue = DispatchQueue(label: "com.chungxon.memstats.sampling", qos: .utility)

  private var timer: DispatchSourceTimer?

  init(startSampling: Bool = true) {
    memoryVM = MemoryViewModel()
    processVM = ProcessViewModel()
    memoryService = MemoryStatsService()
    processService = ProcessSnapshotService()

    if startSampling {
      restartSamplingTimer()
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
  }

  func samplingInterval(for mode: SamplingMode) -> TimeInterval {
    switch mode {
    case .active:
      return 5
    case .idle:
      return 15
    }
  }

  private func restartSamplingTimer() {
    timer?.cancel()

    let nextTimer = DispatchSource.makeTimerSource(queue: samplingQueue)
    nextTimer.schedule(
      deadline: .now(),
      repeating: samplingInterval(for: samplingMode)
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
    let memoryService = memoryService
    let processService = processService

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
        try processService.fetchProcesses(includeRootUser: true, includeSystemUsers: true)
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
    }
    refreshDonutSlices()
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

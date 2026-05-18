import Combine
import Foundation

@MainActor
final class RamStatsAppState: ObservableObject {
  enum SamplingMode: Equatable {
    case active
    case idle
  }

  @Published private(set) var samplingMode: SamplingMode = .idle
  @Published private(set) var lastSamplingError: String?

  let memoryVM: MemoryViewModel
  let processVM: ProcessViewModel

  private let memoryService: MemoryStatsService
  private let processService: ProcessSnapshotService
  private let samplingQueue = DispatchQueue(label: "com.chungxon.ramstats.sampling", qos: .utility)

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
      let sampledAt = Date()

      let memoryResult = Result { try memoryService.fetchMemoryStats() }
      let processResult = Result { try processService.fetchTopProcesses(limit: 20) }

      Task { @MainActor [weak self] in
        guard let self else { return }

        var messages: [String] = []

        switch memoryResult {
        case .success(let stats):
          memoryVM.apply(stats: stats, sampledAt: sampledAt)
        case .failure(let error):
          messages.append("Memory: \(error.localizedDescription)")
        }

        switch processResult {
        case .success(let processes):
          processVM.apply(snapshots: processes)
        case .failure(let error):
          messages.append("Process: \(error.localizedDescription)")
        }

        lastSamplingError = messages.isEmpty ? nil : messages.joined(separator: " | ")
      }
    }
  }
}

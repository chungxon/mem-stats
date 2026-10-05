import Foundation

/// Runs one kind of sample on its own repeating timer. Only one run is in flight at a time:
/// a timer tick that lands during a run is dropped, and an explicit `sampleNow()` during a run
/// queues exactly one follow-up run.
@MainActor
final class PeriodicSampler {
  /// Starts one run. The work must call `completion` on the main actor when it finishes.
  typealias Run = (_ completion: @escaping @MainActor () -> Void) -> Void

  private let timerQueue: DispatchQueue
  private let run: Run

  private var timer: DispatchSourceTimer?
  private(set) var interval: TimeInterval = 0
  private(set) var lastSampleAt: Date?
  private(set) var isSampling = false
  private var needsResample = false
  private var generation = 0

  var isScheduled: Bool {
    timer != nil
  }

  init(timerQueue: DispatchQueue, run: @escaping Run) {
    self.timerQueue = timerQueue
    self.run = run
  }

  deinit {
    timer?.cancel()
  }

  /// (Re)starts the timer. By default it samples right away unless a run started less than
  /// 2s ago. With `waitsFullInterval`, the next run lands one interval after the last one.
  func start(interval: TimeInterval, waitsFullInterval: Bool = false) {
    timer?.cancel()
    self.interval = interval
    // A tick from the old timer may already be queued on the main actor; drop it.
    generation &+= 1
    let timerGeneration = generation

    let delay = Self.initialDelay(
      lastSampleAt: lastSampleAt,
      now: Date(),
      interval: interval,
      minimumGap: waitsFullInterval ? .infinity : 2
    )
    let nextTimer = DispatchSource.makeTimerSource(queue: timerQueue)
    nextTimer.schedule(deadline: .now() + delay, repeating: interval)
    nextTimer.setEventHandler { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.generation == timerGeneration else { return }
        self.perform(coalescesWhenBusy: false)
      }
    }

    timer = nextTimer
    nextTimer.resume()
  }

  /// Samples now and counts the next tick from this run. If a run is in flight, one more runs
  /// right after it instead.
  func sampleNow() {
    perform(coalescesWhenBusy: true)
    if isScheduled, !needsResample {
      start(interval: interval, waitsFullInterval: true)
    }
  }

  /// Delay before the first run after a restart. A run taken moments ago is reused instead of
  /// sampling again right away.
  nonisolated static func initialDelay(
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

  private func perform(coalescesWhenBusy: Bool) {
    guard !isSampling else {
      if coalescesWhenBusy {
        needsResample = true
      }
      return
    }

    isSampling = true
    lastSampleAt = Date()
    run { [weak self] in
      self?.finish()
    }
  }

  private func finish() {
    isSampling = false
    guard needsResample else { return }

    needsResample = false
    perform(coalescesWhenBusy: false)
    // Count the next tick from the follow-up run, like a direct `sampleNow()`.
    if isScheduled {
      start(interval: interval, waitsFullInterval: true)
    }
  }
}

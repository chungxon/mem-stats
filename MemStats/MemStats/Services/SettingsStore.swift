import Combine
import Foundation

/// User settings for sampling and list sizes, persisted in `UserDefaults`. Every change applies
/// right away, and a stored value outside the allowed options falls back to its default.
final class SettingsStore: ObservableObject {
  static let memoryIntervalOptions = [1, 2, 3, 5, 10, 15, 30, 60]
  /// `top` takes about 1.4s per run, so processes are never sampled faster than every 3s.
  static let processIntervalOptions = [3, 5, 10, 15, 30, 60]
  static let rowCountOptions = [5, 8, 10, 15, 20]

  static let defaultMemoryInterval = 5
  static let defaultProcessInterval = 5
  static let defaultRowCount = 8
  static let defaultTheme: AppTheme = .system

  static let memoryIntervalKey = "memoryIntervalSeconds"
  static let processIntervalKey = "processIntervalSeconds"
  static let topAppsCountKey = "topAppsCount"
  static let topProcessesCountKey = "topProcessesCount"
  static let themeKey = "theme"

  /// Seconds between memory samples (RAM, pressure, swap, menu bar, history).
  @Published var memoryInterval: Int {
    didSet {
      store(
        \.memoryInterval, key: Self.memoryIntervalKey, options: Self.memoryIntervalOptions,
        fallback: Self.defaultMemoryInterval)
    }
  }

  /// Seconds between process samples (`top`).
  @Published var processInterval: Int {
    didSet {
      store(
        \.processInterval, key: Self.processIntervalKey, options: Self.processIntervalOptions,
        fallback: Self.defaultProcessInterval)
    }
  }

  @Published var topAppsCount: Int {
    didSet {
      store(
        \.topAppsCount, key: Self.topAppsCountKey, options: Self.rowCountOptions,
        fallback: Self.defaultRowCount)
    }
  }

  @Published var topProcessesCount: Int {
    didSet {
      store(
        \.topProcessesCount, key: Self.topProcessesCountKey, options: Self.rowCountOptions,
        fallback: Self.defaultRowCount)
    }
  }

  @Published var theme: AppTheme {
    didSet {
      defaults.set(theme.rawValue, forKey: Self.themeKey)
    }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    memoryInterval = Self.read(
      Self.memoryIntervalKey, from: defaults, options: Self.memoryIntervalOptions,
      fallback: Self.defaultMemoryInterval)
    processInterval = Self.read(
      Self.processIntervalKey, from: defaults, options: Self.processIntervalOptions,
      fallback: Self.defaultProcessInterval)
    topAppsCount = Self.read(
      Self.topAppsCountKey, from: defaults, options: Self.rowCountOptions,
      fallback: Self.defaultRowCount)
    topProcessesCount = Self.read(
      Self.topProcessesCountKey, from: defaults, options: Self.rowCountOptions,
      fallback: Self.defaultRowCount)
    theme = Self.readTheme(from: defaults)
  }

  private static func readTheme(from defaults: UserDefaults) -> AppTheme {
    guard let rawValue = defaults.string(forKey: themeKey),
      let theme = AppTheme(rawValue: rawValue)
    else {
      return defaultTheme
    }
    return theme
  }

  private static func read(
    _ key: String,
    from defaults: UserDefaults,
    options: [Int],
    fallback: Int
  ) -> Int {
    guard let value = defaults.object(forKey: key) as? Int, options.contains(value) else {
      return fallback
    }
    return value
  }

  private func store(
    _ keyPath: ReferenceWritableKeyPath<SettingsStore, Int>,
    key: String,
    options: [Int],
    fallback: Int
  ) {
    let value = self[keyPath: keyPath]
    guard options.contains(value) else {
      // Setting the fallback runs `didSet` again, which then stores it.
      self[keyPath: keyPath] = fallback
      return
    }
    defaults.set(value, forKey: key)
  }
}

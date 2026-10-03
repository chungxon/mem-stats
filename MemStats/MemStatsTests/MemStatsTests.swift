import Foundation
import ServiceManagement
import Testing

@testable import MemStats

struct MemStatsTests {
  private struct StubMemoryStatsProvider: MemoryStatsProviding {
    nonisolated func fetchMemoryStats() throws -> MemoryStats {
      MemoryStats(
        totalBytes: 1_000,
        usedBytes: 600,
        freeBytes: 400,
        activeBytes: 0,
        inactiveBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        swapUsedBytes: 0,
        pressureLevel: .normal
      )
    }
  }

  /// Blocks the first fetch until `releaseFirstFetch()`, so a test can request samples while
  /// one is still running.
  private final class GatedProcessProvider: ProcessSnapshotProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    // Guarded by `lock`.
    nonisolated(unsafe) private var calls = 0

    nonisolated var fetchCount: Int {
      lock.withLock { calls }
    }

    nonisolated func releaseFirstFetch() {
      gate.signal()
    }

    nonisolated func fetchProcesses(includeRootUser: Bool, includeSystemUsers: Bool) throws
      -> [ProcessSnapshot]
    {
      let call = lock.withLock {
        calls += 1
        return calls
      }
      if call == 1 {
        gate.wait()
      }
      return [ProcessSnapshot(user: "alice", pid: 1, rssBytes: 500, command: "/a")]
    }

    nonisolated func fetchTopProcesses(
      limit: Int,
      includeRootUser: Bool,
      includeSystemUsers: Bool
    ) throws -> [ProcessSnapshot] {
      try fetchProcesses(includeRootUser: includeRootUser, includeSystemUsers: includeSystemUsers)
    }
  }

  private final class MockLoginItemRegistrant: LoginItemRegistrant {
    var status: SMAppService.Status
    var statusAfterRegister: SMAppService.Status
    var didRegister = false
    var didUnregister = false

    init(
      status: SMAppService.Status = .notRegistered,
      statusAfterRegister: SMAppService.Status = .enabled
    ) {
      self.status = status
      self.statusAfterRegister = statusAfterRegister
    }

    func register() throws {
      didRegister = true
      status = statusAfterRegister
    }

    func unregister() throws {
      didUnregister = true
      status = .notRegistered
    }
  }

  @Test func donutBuilderMergesTinyUsersAndKeepsFreeLast() {
    let snapshots = [
      ProcessSnapshot(user: "alice", pid: 1, rssBytes: 500, command: "/a"),
      ProcessSnapshot(user: "bob", pid: 2, rssBytes: 30, command: "/b"),
      ProcessSnapshot(user: "carol", pid: 3, rssBytes: 10, command: "/c"),
    ]

    let slices = DonutDataBuilder.buildSlices(
      totalBytes: 1_000,
      freeBytes: 400,
      snapshots: snapshots,
      tinyThreshold: 0.05
    )

    #expect(slices.count == 4)
    #expect(slices[0].label == "alice")
    #expect(slices[1].label == "Others")
    #expect(slices[2].label == "Unattributed Used")
    #expect(slices[2].bytes == 60)
    #expect(slices[3].label == "Free")
    #expect(slices[3].bytes == 400)
  }

  @Test func donutBuilderNormalizesUserBytesWhenMeasuredExceedsUsed() {
    let snapshots = [
      ProcessSnapshot(user: "alice", pid: 1, rssBytes: 800, command: "/a"),
      ProcessSnapshot(user: "bob", pid: 2, rssBytes: 600, command: "/b"),
    ]

    let slices = DonutDataBuilder.buildSlices(
      totalBytes: 1_000,
      freeBytes: 600,
      snapshots: snapshots
    )

    let totalSliceBytes = slices.reduce(UInt64(0)) { $0 + $1.bytes }
    let hasUnattributed = slices.contains { $0.label == "Unattributed Used" }

    #expect(totalSliceBytes == 1_000)
    #expect(hasUnattributed == false)
  }

  @Test func donutSelectionPicksExpectedSlice() {
    let slices = [
      DonutSlice(id: "a", label: "A", category: .user("a"), bytes: 300, fractionOfTotal: 0.3),
      DonutSlice(id: "b", label: "B", category: .user("b"), bytes: 200, fractionOfTotal: 0.2),
      DonutSlice(id: "f", label: "Free", category: .free, bytes: 500, fractionOfTotal: 0.5),
    ]

    let picked = DonutDataBuilder.sliceForSelection(angleValue: 450, in: slices)

    #expect(picked?.label == "B")
  }

  @MainActor @Test func memoryViewModelKeepsBoundedHistory() {
    let vm = MemoryViewModel(maxSamples: 3)
    let baseStats = MemoryStats(
      totalBytes: 1000,
      usedBytes: 500,
      freeBytes: 500,
      activeBytes: 100,
      inactiveBytes: 100,
      wiredBytes: 100,
      compressedBytes: 100,
      swapUsedBytes: 100,
      pressureLevel: .normal
    )

    vm.apply(stats: baseStats, sampledAt: Date(timeIntervalSince1970: 1))
    vm.apply(stats: baseStats, sampledAt: Date(timeIntervalSince1970: 2))
    vm.apply(stats: baseStats, sampledAt: Date(timeIntervalSince1970: 3))
    vm.apply(stats: baseStats, sampledAt: Date(timeIntervalSince1970: 4))

    #expect(vm.history.count == 3)
    #expect(vm.history[0].timestamp == Date(timeIntervalSince1970: 2))
    #expect(vm.history[2].timestamp == Date(timeIntervalSince1970: 4))
  }

  @MainActor @Test func memoryViewModelMakesTimestampsMonotonic() {
    let vm = MemoryViewModel(maxSamples: 3)
    let baseStats = MemoryStats(
      totalBytes: 1000,
      usedBytes: 500,
      freeBytes: 500,
      activeBytes: 100,
      inactiveBytes: 100,
      wiredBytes: 100,
      compressedBytes: 100,
      swapUsedBytes: 100,
      pressureLevel: .normal
    )

    let sampleTime = Date(timeIntervalSince1970: 1)
    vm.apply(stats: baseStats, sampledAt: sampleTime)
    vm.apply(stats: baseStats, sampledAt: sampleTime)

    #expect(vm.history.count == 2)
    #expect(vm.history[1].timestamp > vm.history[0].timestamp)
  }

  @MainActor @Test func processViewModelResetsMissingSelectedUser() {
    let vm = ProcessViewModel()
    vm.selectedUser = "alice"

    vm.apply(
      snapshots: [
        ProcessSnapshot(user: "bob", pid: 1, rssBytes: 1024, command: "/bin/test")
      ]
    )

    #expect(vm.selectedUser == nil)
  }

  @MainActor @Test func processViewModelFiltersBySelectedUser() {
    let vm = ProcessViewModel()
    vm.apply(
      snapshots: [
        ProcessSnapshot(user: "alice", pid: 1, rssBytes: 1024, command: "/bin/a"),
        ProcessSnapshot(user: "bob", pid: 2, rssBytes: 2048, command: "/bin/b"),
      ]
    )

    vm.selectedUser = "alice"

    #expect(vm.visibleProcesses.count == 1)
    #expect(vm.visibleProcesses.first?.user == "alice")
  }

  @MainActor @Test func processViewModelSelectedUserUsesTopLimitFromAllProcesses() {
    let vm = ProcessViewModel(topProcessesLimit: 2)
    vm.apply(
      snapshots: [
        ProcessSnapshot(user: "bob", pid: 1, rssBytes: 900, command: "/bin/b1"),
        ProcessSnapshot(user: "alice", pid: 2, rssBytes: 800, command: "/bin/a1"),
        ProcessSnapshot(user: "alice", pid: 3, rssBytes: 700, command: "/bin/a2"),
        ProcessSnapshot(user: "alice", pid: 4, rssBytes: 600, command: "/bin/a3"),
      ]
    )

    vm.selectedUser = "alice"

    #expect(vm.topProcesses.count == 2)
    #expect(vm.visibleProcesses.count == 2)
    #expect(vm.visibleProcesses[0].pid == 2)
    #expect(vm.visibleProcesses[1].pid == 3)
  }

  @MainActor @Test func processViewModelTracksSelectedUserHistoryWithBounds() {
    let vm = ProcessViewModel(maxSamples: 2)

    vm.apply(
      snapshots: [
        ProcessSnapshot(user: "alice", pid: 1, rssBytes: 100, command: "/bin/a")
      ],
      sampledAt: Date(timeIntervalSince1970: 1)
    )
    vm.apply(
      snapshots: [
        ProcessSnapshot(user: "alice", pid: 1, rssBytes: 200, command: "/bin/a")
      ],
      sampledAt: Date(timeIntervalSince1970: 2)
    )
    vm.apply(
      snapshots: [
        ProcessSnapshot(user: "alice", pid: 1, rssBytes: 300, command: "/bin/a")
      ],
      sampledAt: Date(timeIntervalSince1970: 3)
    )

    vm.selectedUser = "alice"

    #expect(vm.selectedUserHistory.count == 2)
    #expect(vm.selectedUserHistory[0].timestamp == Date(timeIntervalSince1970: 2))
    #expect(vm.selectedUserHistory[1].rssBytes == 300)
  }

  @MainActor @Test func processViewModelMakesUserHistoryTimestampsMonotonic() {
    let vm = ProcessViewModel(maxSamples: 3)
    let snapshots = [
      ProcessSnapshot(user: "alice", pid: 1, rssBytes: 100, command: "/bin/a")
    ]
    let sampleTime = Date(timeIntervalSince1970: 1)

    vm.apply(snapshots: snapshots, sampledAt: sampleTime)
    vm.apply(snapshots: snapshots, sampledAt: sampleTime)
    vm.selectedUser = "alice"

    #expect(vm.selectedUserHistory.count == 2)
    #expect(vm.selectedUserHistory[1].timestamp > vm.selectedUserHistory[0].timestamp)
  }

  @MainActor @Test func processViewModelScalesUserHistoryToUsedRAMForDisplay() {
    let vm = ProcessViewModel(maxSamples: 3)
    // Summed RSS (400) is double the used RAM (200), so display bytes are halved.
    vm.apply(
      snapshots: [
        ProcessSnapshot(user: "alice", pid: 1, rssBytes: 300, command: "/bin/a"),
        ProcessSnapshot(user: "bob", pid: 2, rssBytes: 100, command: "/bin/b"),
      ],
      targetUsedBytes: 200,
      sampledAt: Date(timeIntervalSince1970: 1)
    )
    vm.selectedUser = "alice"

    #expect(vm.selectedUserHistory.last?.rssBytes == 300)
    #expect(vm.selectedUserHistory.last?.displayBytes == 150)
    #expect(vm.history(for: "bob").last?.displayBytes == 50)
  }

  @MainActor @Test func processViewModelCapsTopProcessesToLimit() {
    let vm = ProcessViewModel()
    let snapshots = (1...30).map { index in
      ProcessSnapshot(
        user: "u\(index)",
        pid: Int32(index),
        rssBytes: UInt64((31 - index) * 100),
        command: "/bin/\(index)"
      )
    }

    vm.apply(snapshots: snapshots)

    #expect(vm.allProcesses.count == 30)
    #expect(vm.topProcesses.count == 8)
    #expect(vm.topProcesses.first?.pid == 1)
    #expect(vm.topProcesses.last?.pid == 8)
  }

  @MainActor @Test func processViewModelApplyEmptySnapshotsClearsVisibleState() {
    let vm = ProcessViewModel()
    vm.apply(
      snapshots: [
        ProcessSnapshot(user: "alice", pid: 1, rssBytes: 1024, command: "/bin/a")
      ]
    )
    vm.selectedUser = "alice"

    vm.apply(snapshots: [])

    #expect(vm.allProcesses.isEmpty)
    #expect(vm.topProcesses.isEmpty)
    #expect(vm.visibleProcesses.isEmpty)
    #expect(vm.selectedUser == nil)
  }

  @Test func parseTopOutputSortsByMemoryDescending() {
    let output = """
      100 son 400M /usr/bin/vim
      1 root 900M /sbin/launchd
      44 son 650M /Applications/Xcode.app
      """

    let snapshots = TopProcessSnapshotParser.parse(
      topOutput: output,
      limit: 8,
      includeRootUser: false
    )

    #expect(snapshots.count == 2)
    #expect(snapshots[0].pid == 44)
    #expect(snapshots[1].pid == 100)
  }

  @Test func parseTopOutputFiltersUnderscoreUsersAndCanIncludeRoot() {
    let output = """
      10 _windowserver 500M /System/Library/windowserver
      1 root 900M /sbin/launchd
      44 son 650M /Applications/Xcode.app
      """

    let defaultFiltered = TopProcessSnapshotParser.parse(
      topOutput: output,
      limit: 8,
      includeRootUser: false,
      includeSystemUsers: false
    )
    #expect(defaultFiltered.count == 1)
    #expect(defaultFiltered[0].user == "son")

    let withRoot = TopProcessSnapshotParser.parse(
      topOutput: output,
      limit: 8,
      includeRootUser: true,
      includeSystemUsers: false
    )
    #expect(withRoot.count == 2)
    #expect(withRoot[0].user == "root")
    #expect(withRoot[1].user == "son")
  }

  @Test func parseTopOutputDefaultsToAllUsersIncludingSystemAndRoot() {
    let output = """
      10 _windowserver 500M /System/Library/windowserver
      1 root 900M /sbin/launchd
      44 son 650M /Applications/Xcode.app
      """

    let snapshots = TopProcessSnapshotParser.parse(topOutput: output, limit: 8)
    #expect(snapshots.count == 3)
    #expect(snapshots[0].user == "root")
    #expect(snapshots[1].user == "son")
    #expect(snapshots[2].user == "_windowserver")
  }

  @Test func parseTopOutputCapsAtLimit() {
    let lines = (1...30).map { index in
      "\(index) u\(index) \(index)M /cmd/\(index)"
    }
    let output = lines.joined(separator: "\n")

    let snapshots = TopProcessSnapshotParser.parse(topOutput: output, limit: 8)

    #expect(snapshots.count == 8)
    #expect(snapshots.first?.pid == 30)
    #expect(snapshots.last?.pid == 23)
  }

  @Test func parseTopOutputReturnsAllWhenNoLimitProvided() {
    let output = """
      100 son 400M /usr/bin/vim
      44 son 650M /Applications/Xcode.app
      45 son 300M /Applications/Code.app
      """

    let snapshots = TopProcessSnapshotParser.parse(topOutput: output, limit: nil)

    #expect(snapshots.count == 3)
    #expect(snapshots.first?.pid == 44)
    #expect(snapshots.last?.pid == 45)
  }

  @Test func parseTopOutputKeepsFullCommandLineWhenUsingCommandField() {
    let output = """
      19538 son 2.88G lldb-rpc-server --stdio --foo bar
      53462 son 2.57G dart:dartdev_aot.dart.snapshot --packages=.dart_tool/package_config.json
      """

    let snapshots = TopProcessSnapshotParser.parse(topOutput: output, limit: nil)

    #expect(snapshots.count == 2)
    #expect(snapshots[0].pid == 19538)
    #expect(snapshots[0].command == "lldb-rpc-server --stdio --foo bar")
    #expect(snapshots[1].pid == 53462)
    #expect(
      snapshots[1].command
        == "dart:dartdev_aot.dart.snapshot --packages=.dart_tool/package_config.json"
    )
  }

  @Test func appIdentityGroupsHelperIntoOutermostAppBundle() {
    let main = AppIdentityResolver.identity(
      forExecutablePath: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"
    )
    let helper = AppIdentityResolver.identity(
      forExecutablePath:
        "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Renderer).app/Contents/MacOS/Code Helper (Renderer)"
    )

    #expect(main.id == helper.id)
    #expect(helper.name == "Visual Studio Code")
    #expect(helper.path == "/Applications/Visual Studio Code.app")
  }

  @Test func appIdentityUsesExecutableNameOutsideAppBundle() {
    let identity = AppIdentityResolver.identity(forExecutablePath: "/usr/local/bin/mysqld")

    #expect(identity.id == "exec:/usr/local/bin/mysqld")
    #expect(identity.name == "mysqld")
  }

  @Test func appAggregatorSumsMemoryAndSortsDescending() {
    let code = AppIdentity(id: "app:/Code.app", name: "Code", path: "/Code.app")
    let edge = AppIdentity(id: "app:/Edge.app", name: "Edge", path: "/Edge.app")
    let processes = [
      ProcessSnapshot(user: "son", pid: 1, rssBytes: 300, command: "Code"),
      ProcessSnapshot(user: "son", pid: 2, rssBytes: 400, command: "Code Helper"),
      ProcessSnapshot(user: "son", pid: 3, rssBytes: 500, command: "Microsoft Edge"),
      ProcessSnapshot(user: "son", pid: 4, rssBytes: 50, command: "unknownd"),
    ]

    let apps = AppMemoryAggregator.aggregate(
      processes: processes,
      identities: [1: code, 2: code, 3: edge]
    )

    #expect(apps.count == 3)
    #expect(apps[0].name == "Code")
    #expect(apps[0].bytes == 700)
    #expect(apps[0].processCount == 2)
    #expect(apps[1].name == "Edge")
    #expect(apps[2].name == "unknownd")
    #expect(apps[2].path == nil)
  }

  @MainActor @Test func processViewModelScopesAppsToSelectedUser() {
    let app = AppIdentity(id: "app:/A.app", name: "A", path: "/A.app")
    let vm = ProcessViewModel()
    vm.apply(
      snapshots: [
        ProcessSnapshot(user: "bob", pid: 1, rssBytes: 900, command: "A"),
        ProcessSnapshot(user: "alice", pid: 2, rssBytes: 100, command: "A"),
      ],
      appIdentities: [1: app, 2: app]
    )

    #expect(vm.visibleApps.first?.bytes == 1_000)

    vm.selectedUser = "alice"

    #expect(vm.visibleApps.count == 1)
    #expect(vm.visibleApps.first?.bytes == 100)
    #expect(vm.visibleApps.first?.processCount == 1)
  }

  @Test func memoryStatsServiceReturnsPositiveTotals() throws {
    let service = MemoryStatsService()
    let stats = try service.fetchMemoryStats()

    #expect(stats.totalBytes > 0)
    #expect(stats.usedBytes <= stats.totalBytes)
    #expect(stats.freeBytes <= stats.totalBytes)
    #expect(stats.usedBytes + stats.freeBytes == stats.totalBytes)
  }

  @Test func donutPaletteIndexIsStableAndInRange() {
    // FNV-1a("alice") = 0x508b2abb65a03907, so the index never changes between launches.
    #expect(DonutDataBuilder.paletteIndex(for: "alice", paletteCount: 8) == 7)
    #expect(DonutDataBuilder.paletteIndex(for: "", paletteCount: 8) < 8)
    #expect(DonutDataBuilder.paletteIndex(for: "root", paletteCount: 0) == 0)
  }

  @Test func historySegmentsPairAdjacentSamplesAndUseEndPressure() {
    let start = Date(timeIntervalSince1970: 1_000)
    let samples = [
      MemoryHistorySample(
        timestamp: start, usedBytes: 10, swapUsedBytes: 0, pressureLevel: .normal),
      MemoryHistorySample(
        timestamp: start.addingTimeInterval(5), usedBytes: 20, swapUsedBytes: 0,
        pressureLevel: .warning),
      MemoryHistorySample(
        timestamp: start.addingTimeInterval(10), usedBytes: 15, swapUsedBytes: 0,
        pressureLevel: .normal),
    ]

    let points = MemoryHistorySegmentPoint.segments(from: samples)

    #expect(points.count == 4)
    #expect(Set(points.map(\.segmentID)).count == 2)
    #expect(Set(points.map(\.id)).count == 4)
    #expect(points.map(\.usedBytes) == [10, 20, 20, 15])
    #expect(points.map(\.pressureLevel) == [.warning, .warning, .normal, .normal])
    #expect(MemoryHistorySegmentPoint.segments(from: Array(samples.prefix(1))).isEmpty)
  }

  @Test func usedMemoryCountsAppWiredAndCompressedPages() {
    let used = MemoryStatsService.usedMemoryBytes(
      internalPages: 100,
      purgeablePages: 20,
      wiredPages: 30,
      compressedPages: 10,
      pageSize: 4,
      totalBytes: 10_000
    )
    #expect(used == (80 + 30 + 10) * 4)
  }

  @Test func usedMemoryClampsPurgeableAndTotal() {
    let noAppMemory = MemoryStatsService.usedMemoryBytes(
      internalPages: 10,
      purgeablePages: 50,
      wiredPages: 5,
      compressedPages: 0,
      pageSize: 1,
      totalBytes: 100
    )
    #expect(noAppMemory == 5)

    let capped = MemoryStatsService.usedMemoryBytes(
      internalPages: 1_000,
      purgeablePages: 0,
      wiredPages: 0,
      compressedPages: 0,
      pageSize: 1,
      totalBytes: 100
    )
    #expect(capped == 100)
  }

  @Test func memorystatusPressureMappingUsesExpectedBands() {
    #expect(MemoryStatsService.levelFromMemorystatusPressure(1) == .normal)
    #expect(MemoryStatsService.levelFromMemorystatusPressure(2) == .warning)
    #expect(MemoryStatsService.levelFromMemorystatusPressure(4) == .critical)
  }

  @Test func effectiveIntervalUsesSettingWhenActiveAndAtLeast15sWhenIdle() {
    #expect(MemStatsAppState.effectiveInterval(setting: 5, mode: .active) == 5)
    #expect(MemStatsAppState.effectiveInterval(setting: 1, mode: .active) == 1)
    #expect(MemStatsAppState.effectiveInterval(setting: 5, mode: .idle) == 15)
    #expect(MemStatsAppState.effectiveInterval(setting: 15, mode: .idle) == 15)
    #expect(MemStatsAppState.effectiveInterval(setting: 30, mode: .idle) == 30)
  }

  @Test func historyCapacityKeepsAboutTenMinutes() {
    #expect(MemStatsAppState.historyCapacity(interval: 5) == 120)
    #expect(MemStatsAppState.historyCapacity(interval: 1) == 600)
    #expect(MemStatsAppState.historyCapacity(interval: 3) == 200)
    #expect(MemStatsAppState.historyCapacity(interval: 60) == 10)
    #expect(MemStatsAppState.historyCapacity(interval: 0) == 600)
  }

  @Test func settingsStoreUsesDefaultsPersistsAndRejectsInvalidValues() {
    let suiteName = "MemStatsTests.SettingsStore"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = SettingsStore(defaults: defaults)
    #expect(store.memoryInterval == 5)
    #expect(store.processInterval == 5)
    #expect(store.topAppsCount == 8)
    #expect(store.topProcessesCount == 8)

    store.memoryInterval = 2
    store.processInterval = 30
    store.topAppsCount = 15
    store.topProcessesCount = 20
    let restored = SettingsStore(defaults: defaults)
    #expect(restored.memoryInterval == 2)
    #expect(restored.processInterval == 30)
    #expect(restored.topAppsCount == 15)
    #expect(restored.topProcessesCount == 20)

    // A value outside the options falls back to the default, both when set and when read.
    restored.processInterval = 1
    #expect(restored.processInterval == 5)
    #expect(defaults.integer(forKey: SettingsStore.processIntervalKey) == 5)

    defaults.set(7, forKey: SettingsStore.memoryIntervalKey)
    defaults.set("many", forKey: SettingsStore.topAppsCountKey)
    defaults.set(0, forKey: SettingsStore.topProcessesCountKey)
    let invalid = SettingsStore(defaults: defaults)
    #expect(invalid.memoryInterval == 5)
    #expect(invalid.topAppsCount == 8)
    #expect(invalid.topProcessesCount == 8)
  }

  @MainActor @Test func processViewModelUsesSeparateLimitsForAppsAndProcesses() {
    let vm = ProcessViewModel(topAppsLimit: 2, topProcessesLimit: 5)
    let snapshots = (1...10).map { index in
      ProcessSnapshot(
        user: "alice",
        pid: Int32(index),
        rssBytes: UInt64((11 - index) * 100),
        command: "/bin/tool\(index)"
      )
    }
    vm.apply(snapshots: snapshots)

    #expect(vm.topProcesses.count == 5)
    #expect(vm.visibleApps.count == 2)

    // Changing the row counts re-slices the current snapshot without a new sample.
    vm.setLimits(topApps: 8, topProcesses: 3)
    #expect(vm.topProcesses.map(\.pid) == [1, 2, 3])
    #expect(vm.visibleApps.count == 8)

    vm.selectedUser = "alice"
    #expect(vm.visibleProcesses.count == 3)
  }

  @MainActor @Test func appStateAppliesRowCountAndHistorySettings() {
    let suiteName = "MemStatsTests.AppStateSettings"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let appState = MemStatsAppState(startSampling: false, defaults: defaults)
    #expect(appState.memoryVM.maxSamples == 120)
    #expect(appState.processVM.topProcessesLimit == 8)

    appState.settings.memoryInterval = 1
    appState.settings.processInterval = 10
    appState.settings.topAppsCount = 5
    appState.settings.topProcessesCount = 15

    #expect(appState.memoryVM.maxSamples == 600)
    #expect(appState.processVM.maxSamples == 60)
    #expect(appState.processVM.topAppsLimit == 5)
    #expect(appState.processVM.topProcessesLimit == 15)
  }

  @Test func growthDetectorFlagsContinuousGrowth() {
    let mb: UInt64 = 1024 * 1024
    let total: UInt64 = 16 * 1024 * mb
    let growing = (0..<12).map { UInt64($0) * 20 * mb + 1_000 * mb }

    let hint = MemoryGrowthDetector.hint(user: "alice", history: growing, totalBytes: total)
    #expect(
      hint
        == MemoryGrowthHint(
          user: "alice", kind: .continuousGrowth(samples: 12), growthBytes: 220 * mb))

    // One dip in the window breaks the streak.
    var withDip = growing
    withDip[6] = withDip[5]
    #expect(MemoryGrowthDetector.hint(user: "alice", history: withDip, totalBytes: total) == nil)

    // Too few samples, or growth too small to matter.
    let shortHistory = Array(growing.prefix(11))
    let shortHint = MemoryGrowthDetector.hint(
      user: "alice", history: shortHistory, totalBytes: total)
    #expect(shortHint == nil)
    let tinyGrowth = (0..<12).map { UInt64($0) * mb + 1_000 * mb }
    #expect(MemoryGrowthDetector.hint(user: "alice", history: tinyGrowth, totalBytes: total) == nil)
  }

  @MainActor @Test func processViewModelResetsHistoryForUsersThatDisappear() {
    let vm = ProcessViewModel()
    let start = Date(timeIntervalSince1970: 1_000)
    let alice = ProcessSnapshot(user: "alice", pid: 1, rssBytes: 100, command: "/a")
    let bob = ProcessSnapshot(user: "bob", pid: 2, rssBytes: 50, command: "/b")

    vm.apply(snapshots: [alice, bob], sampledAt: start)
    vm.apply(snapshots: [bob], sampledAt: start.addingTimeInterval(5))
    vm.apply(snapshots: [alice, bob], sampledAt: start.addingTimeInterval(10))

    #expect(vm.history(for: "alice").count == 1)
    #expect(vm.history(for: "bob").count == 3)
  }

  @Test func growthDetectorFlagsSuddenJumpAboveThreshold() {
    let mb: UInt64 = 1024 * 1024
    let total: UInt64 = 16 * 1024 * mb  // 5% = ~819 MB, above the 500 MB floor.

    let jump = MemoryGrowthDetector.hint(
      user: "bob", history: [1_000 * mb, 1_900 * mb], totalBytes: total)
    #expect(jump == MemoryGrowthHint(user: "bob", kind: .suddenJump, growthBytes: 900 * mb))

    let belowThreshold = MemoryGrowthDetector.hint(
      user: "bob", history: [1_000 * mb, 1_700 * mb], totalBytes: total)
    #expect(belowThreshold == nil)

    let drop = MemoryGrowthDetector.hint(
      user: "bob", history: [1_900 * mb, 1_000 * mb], totalBytes: total)
    #expect(drop == nil)
  }

  @Test func initialSamplingDelaySkipsResampleRightAfterASample() {
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(PeriodicSampler.initialDelay(lastSampleAt: nil, now: now, interval: 5) == 0)
    #expect(
      PeriodicSampler.initialDelay(
        lastSampleAt: now.addingTimeInterval(-0.5), now: now, interval: 5) == 4.5)
    #expect(
      PeriodicSampler.initialDelay(
        lastSampleAt: now.addingTimeInterval(-3), now: now, interval: 5) == 0)
    // Clock moved backwards: sample right away instead of waiting.
    #expect(
      PeriodicSampler.initialDelay(
        lastSampleAt: now.addingTimeInterval(10), now: now, interval: 5) == 0)
  }

  @Test func initialSamplingDelayWaitsFullIntervalWhenPopoverCloses() {
    let now = Date(timeIntervalSince1970: 1_000)

    // Closing never samples right away: the next sample lands one idle interval after the last.
    #expect(
      PeriodicSampler.initialDelay(
        lastSampleAt: now.addingTimeInterval(-3), now: now, interval: 15, minimumGap: .infinity
      ) == 12)
    #expect(
      PeriodicSampler.initialDelay(
        lastSampleAt: now.addingTimeInterval(-20), now: now, interval: 15, minimumGap: .infinity
      ) == 0)
  }

  @MainActor @Test func periodicSamplerRunsOneFollowUpForRequestsDuringARun() {
    var runs = 0
    var pendingCompletion: (@MainActor () -> Void)?
    let sampler = PeriodicSampler(timerQueue: DispatchQueue(label: "test.sampler")) { completion in
      runs += 1
      pendingCompletion = completion
    }

    sampler.sampleNow()
    #expect(runs == 1)
    #expect(sampler.isSampling)

    // Several requests during a run collapse into one follow-up.
    sampler.sampleNow()
    sampler.sampleNow()
    #expect(runs == 1)

    pendingCompletion?()
    #expect(runs == 2)
    #expect(sampler.isSampling)

    pendingCompletion?()
    #expect(runs == 2)
    #expect(!sampler.isSampling)
  }

  @Test func parseTopMemoryTokenHandlesChangeMarkersAndClamps() {
    #expect(TopProcessSnapshotParser.parseTopMemoryToken("12G+") == UInt64(12) * 1_073_741_824)
    #expect(TopProcessSnapshotParser.parseTopMemoryToken("512K-") == UInt64(512) * 1_024)
    #expect(TopProcessSnapshotParser.parseTopMemoryToken("300M") == UInt64(300) * 1_048_576)
    #expect(TopProcessSnapshotParser.parseTopMemoryToken("99999999999T") == UInt64.max)
    #expect(TopProcessSnapshotParser.parseTopMemoryToken("+") == nil)
    #expect(TopProcessSnapshotParser.parseTopMemoryToken("-5M") == nil)

    let snapshots = TopProcessSnapshotParser.parse(
      topOutput: """
        10 son 12G+ /Applications/Xcode.app
        11 son 512K- /usr/bin/vim
        """,
      limit: nil
    )
    #expect(snapshots.map(\.pid) == [10, 11])
  }

  @MainActor @Test func appStateCoalescesRefreshesWhileSampling() async {
    let processProvider = GatedProcessProvider()
    let appState = MemStatsAppState(
      startSampling: false,
      memoryService: StubMemoryStatsProvider(),
      processService: processProvider
    )

    appState.sampleImmediately()
    #expect(appState.isSampling)
    // Repeated clicks while `top` runs collapse into a single follow-up sample.
    appState.sampleImmediately()
    appState.sampleImmediately()
    appState.sampleImmediately()
    processProvider.releaseFirstFetch()

    var waits = 0
    while (appState.isSampling || processProvider.fetchCount < 2) && waits < 200 {
      try? await Task.sleep(for: .milliseconds(10))
      waits += 1
    }
    // Give a stray third sample a chance to show up before checking the count.
    try? await Task.sleep(for: .milliseconds(50))

    #expect(processProvider.fetchCount == 2)
    #expect(appState.isSampling == false)
    #expect(appState.processVM.allProcesses.count == 1)
  }

  @MainActor @Test func appStatePersistsShowSystemUsersOption() {
    let suiteName = "MemStatsTests.ShowSystemUsers"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let appState = MemStatsAppState(startSampling: false, defaults: defaults)
    #expect(appState.showsSystemUsers == true)

    appState.setShowsSystemUsers(false)
    #expect(appState.showsSystemUsers == false)
    #expect(defaults.bool(forKey: MemStatsAppState.showsSystemUsersKey) == false)

    let restored = MemStatsAppState(startSampling: false, defaults: defaults)
    #expect(restored.showsSystemUsers == false)
  }

  @MainActor @Test func appStateCachesDonutSlicesPerSample() {
    let appState = MemStatsAppState(startSampling: false)
    #expect(appState.donutSlices.isEmpty)

    let stats = MemoryStats(
      totalBytes: 1_000,
      usedBytes: 600,
      freeBytes: 400,
      activeBytes: 0,
      inactiveBytes: 0,
      wiredBytes: 0,
      compressedBytes: 0,
      swapUsedBytes: 0,
      pressureLevel: .normal
    )
    let processes = [
      ProcessSnapshot(user: "alice", pid: 1, rssBytes: 500, command: "/a")
    ]

    appState.applySample(stats: stats, processes: processes)
    #expect(appState.donutSlices.map(\.id) == ["user:alice", "unattributed", "free"])

    // A failed process sample keeps the previous processes for the donut.
    appState.applySample(stats: stats, processes: nil)
    #expect(appState.donutSlices.map(\.id) == ["user:alice", "unattributed", "free"])
  }

  @Test func loginItemServiceSyncsAndPersistsState() {
    let defaults = UserDefaults(suiteName: "MemStatsTests.LoginItem.Sync")!
    defaults.removePersistentDomain(forName: "MemStatsTests.LoginItem.Sync")

    let registrant = MockLoginItemRegistrant(status: .enabled)
    let service = LoginItemService(defaults: defaults, registrant: registrant)

    service.syncWithSystem()

    #expect(service.isEnabled == true)
    #expect(defaults.bool(forKey: "openAtLogin") == true)
  }

  @Test func loginItemServiceToggleCallsRegisterAndUnregister() throws {
    let defaults = UserDefaults(suiteName: "MemStatsTests.LoginItem.Toggle")!
    defaults.removePersistentDomain(forName: "MemStatsTests.LoginItem.Toggle")

    let registrant = MockLoginItemRegistrant(status: .notRegistered)
    let service = LoginItemService(defaults: defaults, registrant: registrant)

    let enabled = try service.toggle()
    #expect(enabled == true)
    #expect(registrant.didRegister == true)
    #expect(defaults.bool(forKey: "openAtLogin") == true)

    let disabled = try service.toggle()
    #expect(disabled == false)
    #expect(registrant.didUnregister == true)
    #expect(defaults.bool(forKey: "openAtLogin") == false)
  }

  @Test func loginItemServiceStaysDisabledWhenApprovalIsRequired() throws {
    let suiteName = "MemStatsTests.LoginItem.Approval"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let registrant = MockLoginItemRegistrant(
      status: .notRegistered,
      statusAfterRegister: .requiresApproval
    )
    let service = LoginItemService(defaults: defaults, registrant: registrant)

    let enabled = try service.toggle()

    #expect(registrant.didRegister == true)
    #expect(enabled == false)
    #expect(service.isEnabled == false)
    #expect(service.requiresApproval == true)
    #expect(defaults.bool(forKey: "openAtLogin") == false)
  }
}

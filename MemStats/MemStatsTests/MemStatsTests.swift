import Foundation
import ServiceManagement
import Testing

@testable import MemStats

struct MemStatsTests {
  private final class MockLoginItemRegistrant: LoginItemRegistrant {
    var status: SMAppService.Status
    var didRegister = false
    var didUnregister = false

    init(status: SMAppService.Status = .notRegistered) {
      self.status = status
    }

    func register() throws {
      didRegister = true
    }

    func unregister() throws {
      didUnregister = true
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
    let vm = ProcessViewModel()
    vm.apply(
      snapshots: [
        ProcessSnapshot(user: "bob", pid: 1, rssBytes: 900, command: "/bin/b1"),
        ProcessSnapshot(user: "alice", pid: 2, rssBytes: 800, command: "/bin/a1"),
        ProcessSnapshot(user: "alice", pid: 3, rssBytes: 700, command: "/bin/a2"),
        ProcessSnapshot(user: "alice", pid: 4, rssBytes: 600, command: "/bin/a3"),
      ],
      topLimit: 2
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

    vm.apply(snapshots: snapshots, topLimit: 8)

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
      ],
      topLimit: 8
    )
    vm.selectedUser = "alice"

    vm.apply(snapshots: [], topLimit: 8)

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
  }

  @Test func vmMemoryPressureMappingUsesExpectedBands() {
    #expect(MemoryStatsService.levelFromVMMemoryPressure(0) == .normal)
    #expect(MemoryStatsService.levelFromVMMemoryPressure(1) == .warning)
    #expect(MemoryStatsService.levelFromVMMemoryPressure(2) == .critical)
  }

  @Test func memorystatusPressureMappingUsesExpectedBands() {
    #expect(MemoryStatsService.levelFromMemorystatusPressure(1) == .normal)
    #expect(MemoryStatsService.levelFromMemorystatusPressure(2) == .warning)
    #expect(MemoryStatsService.levelFromMemorystatusPressure(4) == .critical)
  }

  @Test func maxPressureLevelReturnsMostSevereLevel() {
    #expect(MemoryStatsService.maxPressureLevel(.normal, .warning) == .warning)
    #expect(MemoryStatsService.maxPressureLevel(.critical, .warning) == .critical)
  }

  @MainActor @Test func appStateUsesExpectedSamplingIntervals() {
    let appState = MemStatsAppState(startSampling: false)

    #expect(appState.samplingInterval(for: .active) == 5)
    #expect(appState.samplingInterval(for: .idle) == 15)
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
}

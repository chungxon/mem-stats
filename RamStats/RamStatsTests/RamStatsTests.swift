import Foundation
import Testing

@testable import RamStats

struct RamStatsTests {
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

  @Test func parseProcessOutputSortsByRSSDescending() {
    let output = """
      son 100 400 /usr/bin/vim
      root 1 900 /sbin/launchd
      son 44 650 /Applications/Xcode.app
      """

    let snapshots = ProcessSnapshotParser.parse(psOutput: output, limit: 20)

    #expect(snapshots.count == 3)
    #expect(snapshots[0].pid == 1)
    #expect(snapshots[1].pid == 44)
    #expect(snapshots[2].pid == 100)
  }

  @Test func parseProcessOutputCapsAtLimit() {
    let lines = (1...30).map { index in
      "u\(index) \(index) \(index) /cmd/\(index)"
    }
    let output = lines.joined(separator: "\n")

    let snapshots = ProcessSnapshotParser.parse(psOutput: output, limit: 20)

    #expect(snapshots.count == 20)
    #expect(snapshots.first?.pid == 30)
    #expect(snapshots.last?.pid == 11)
  }

  @Test func memoryStatsServiceReturnsPositiveTotals() throws {
    let service = MemoryStatsService()
    let stats = try service.fetchMemoryStats()

    #expect(stats.totalBytes > 0)
    #expect(stats.usedBytes <= stats.totalBytes)
    #expect(stats.freeBytes <= stats.totalBytes)
  }

  @MainActor @Test func appStateUsesExpectedSamplingIntervals() {
    let appState = RamStatsAppState(startSampling: false)

    #expect(appState.samplingInterval(for: .active) == 5)
    #expect(appState.samplingInterval(for: .idle) == 15)
  }
}

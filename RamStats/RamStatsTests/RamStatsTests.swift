import Testing

@testable import RamStats

struct RamStatsTests {
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
}

import Foundation

protocol ProcessSnapshotProviding: Sendable {
  nonisolated func fetchTopProcesses(limit: Int, includeRootUser: Bool) throws -> [ProcessSnapshot]
}

enum ProcessSnapshotServiceError: Error {
  case commandFailed(Int32)
  case utf8DecodeFailed
}

struct ProcessSnapshotService: ProcessSnapshotProviding {
  nonisolated func fetchTopProcesses(
    limit: Int = 20,
    includeRootUser: Bool = false
  ) throws -> [ProcessSnapshot] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "user=,pid=,rss=,comm="]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe

    let errorPipe = Pipe()
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw ProcessSnapshotServiceError.commandFailed(process.terminationStatus)
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: outputData, encoding: .utf8) else {
      throw ProcessSnapshotServiceError.utf8DecodeFailed
    }

    return ProcessSnapshotParser.parse(
      psOutput: output,
      limit: limit,
      includeRootUser: includeRootUser
    )
  }
}

enum ProcessSnapshotParser {
  static func parse(
    psOutput: String,
    limit: Int = 20,
    includeRootUser: Bool = false
  ) -> [ProcessSnapshot] {
    let parsed =
      psOutput
      .split(whereSeparator: \.isNewline)
      .compactMap(parseLine)
      .filter { shouldInclude(user: $0.user, includeRootUser: includeRootUser) }
      .sorted { lhs, rhs in
        if lhs.rssBytes == rhs.rssBytes {
          return lhs.pid < rhs.pid
        }
        return lhs.rssBytes > rhs.rssBytes
      }

    return Array(parsed.prefix(max(limit, 0)))
  }

  private static func parseLine(_ line: Substring) -> ProcessSnapshot? {
    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedLine.isEmpty else { return nil }

    let parts = trimmedLine.split(maxSplits: 3, whereSeparator: \.isWhitespace)
    guard parts.count == 4 else { return nil }

    let user = String(parts[0])
    guard let pid = Int32(parts[1]), let rssKilobytes = UInt64(parts[2]) else {
      return nil
    }

    let command = String(parts[3])
    return ProcessSnapshot(
      user: user,
      pid: pid,
      rssBytes: rssKilobytes * 1024,
      command: command
    )
  }

  private static func shouldInclude(user: String, includeRootUser: Bool) -> Bool {
    if user.hasPrefix("_") {
      return false
    }

    if !includeRootUser && user == "root" {
      return false
    }

    return true
  }
}

import Foundation

protocol ProcessSnapshotProviding: Sendable {
  nonisolated func fetchProcesses(includeRootUser: Bool) throws -> [ProcessSnapshot]
  nonisolated func fetchTopProcesses(limit: Int, includeRootUser: Bool) throws -> [ProcessSnapshot]
}

enum ProcessSnapshotServiceError: Error {
  case commandLaunchFailed(String)
  case commandTimedOut
  case commandFailed(Int32, String)
  case utf8DecodeFailed
}

extension ProcessSnapshotServiceError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .commandLaunchFailed(let message):
      return "Could not launch ps command (\(message))."
    case .commandTimedOut:
      return "ps command timed out."
    case .commandFailed(let code, let details):
      if details.isEmpty {
        return "ps command failed with status \(code)."
      }
      return "ps command failed with status \(code): \(details)"
    case .utf8DecodeFailed:
      return "Could not decode ps command output."
    }
  }
}

struct ProcessSnapshotService: ProcessSnapshotProviding {
  nonisolated func fetchProcesses(includeRootUser: Bool = false) throws -> [ProcessSnapshot] {
    let output = try runPSCommand()
    return ProcessSnapshotParser.parse(
      psOutput: output,
      limit: nil,
      includeRootUser: includeRootUser
    )
  }

  nonisolated func fetchTopProcesses(
    limit: Int = 8,
    includeRootUser: Bool = false
  ) throws -> [ProcessSnapshot] {
    let output = try runPSCommand()
    return ProcessSnapshotParser.parse(
      psOutput: output,
      limit: limit,
      includeRootUser: includeRootUser
    )
  }

  private nonisolated func runPSCommand() throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "user=,pid=,rss=,comm="]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe

    let errorPipe = Pipe()
    process.standardError = errorPipe

    let outputQueue = DispatchQueue(label: "com.chungxon.ramstats.ps.stdout")
    let errorQueue = DispatchQueue(label: "com.chungxon.ramstats.ps.stderr")
    let readGroup = DispatchGroup()
    var outputData = Data()
    var errorData = Data()

    readGroup.enter()
    outputQueue.async {
      outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
      readGroup.leave()
    }

    readGroup.enter()
    errorQueue.async {
      errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      readGroup.leave()
    }

    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
      finished.signal()
    }

    do {
      try process.run()
    } catch {
      throw ProcessSnapshotServiceError.commandLaunchFailed(error.localizedDescription)
    }

    let timeout: DispatchTime = .now() + .seconds(2)
    if finished.wait(timeout: timeout) != .success {
      process.terminate()
      process.waitUntilExit()
      throw ProcessSnapshotServiceError.commandTimedOut
    }

    _ = readGroup.wait(timeout: .now() + .seconds(1))

    guard process.terminationStatus == 0 else {
      let details = String(data: errorData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw ProcessSnapshotServiceError.commandFailed(process.terminationStatus, details)
    }

    guard let output = String(data: outputData, encoding: .utf8) else {
      throw ProcessSnapshotServiceError.utf8DecodeFailed
    }

    return output
  }
}

enum ProcessSnapshotParser {
  nonisolated static func parse(
    psOutput: String,
    limit: Int? = 8,
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

    if let limit {
      return Array(parsed.prefix(max(limit, 0)))
    }

    return parsed
  }

  nonisolated private static func parseLine(_ line: Substring) -> ProcessSnapshot? {
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

  nonisolated private static func shouldInclude(user: String, includeRootUser: Bool) -> Bool {
    if user.hasPrefix("_") {
      return false
    }

    if !includeRootUser && user == "root" {
      return false
    }

    return true
  }
}

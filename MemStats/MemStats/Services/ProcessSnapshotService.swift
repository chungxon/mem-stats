import Darwin
import Foundation

protocol ProcessSnapshotProviding: Sendable {
  nonisolated func fetchProcesses(includeRootUser: Bool, includeSystemUsers: Bool) throws
    -> [ProcessSnapshot]
  nonisolated func fetchTopProcesses(limit: Int, includeRootUser: Bool, includeSystemUsers: Bool)
    throws -> [ProcessSnapshot]
}

enum ProcessSnapshotServiceError: Error, Equatable {
  case commandLaunchFailed(String)
  case commandTimedOut
  case outputReadTimedOut
  case commandFailed(Int32, String)
  case utf8DecodeFailed
}

extension ProcessSnapshotServiceError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .commandLaunchFailed(let message):
      return "Could not launch top command (\(message))."
    case .commandTimedOut:
      return "top command timed out."
    case .outputReadTimedOut:
      return "Could not read top command output in time."
    case .commandFailed(let code, let details):
      if details.isEmpty {
        return "top command failed with status \(code)."
      }
      return "top command failed with status \(code): \(details)"
    case .utf8DecodeFailed:
      return "Could not decode top command output."
    }
  }
}

struct ProcessSnapshotService: ProcessSnapshotProviding {
  typealias TopCommandRunner =
    @Sendable (
      _ processLimit: Int,
      _ timeout: DispatchTimeInterval
    ) throws -> String

  /// Keep the broad snapshot for normal runs so user totals and the donut retain coverage.
  nonisolated static let primaryTopProcessLimit = 500
  /// A smaller snapshot keeps the UI useful when `top` is slow under system load.
  nonisolated static let fallbackTopProcessLimit = 150
  /// `top -l 1 -n 500` is usually quick, but can be much slower when the system is busy.
  nonisolated static let topCommandTimeout: DispatchTimeInterval = .seconds(6)
  nonisolated static let fallbackTopCommandTimeout: DispatchTimeInterval = .seconds(4)

  private let topCommandRunner: TopCommandRunner

  init(topCommandRunner: TopCommandRunner? = nil) {
    self.topCommandRunner =
      topCommandRunner ?? { processLimit, timeout in
        try Self.runTopCommand(processLimit: processLimit, timeout: timeout)
      }
  }

  nonisolated func fetchProcesses(
    includeRootUser: Bool = true,
    includeSystemUsers: Bool = true
  ) throws -> [ProcessSnapshot] {
    let output = try runTopCommandWithFallback()
    return TopProcessSnapshotParser.parse(
      topOutput: output,
      limit: nil,
      includeRootUser: includeRootUser,
      includeSystemUsers: includeSystemUsers
    )
  }

  nonisolated func fetchTopProcesses(
    limit: Int = 8,
    includeRootUser: Bool = true,
    includeSystemUsers: Bool = true
  ) throws -> [ProcessSnapshot] {
    let output = try runTopCommandWithFallback()
    return TopProcessSnapshotParser.parse(
      topOutput: output,
      limit: limit,
      includeRootUser: includeRootUser,
      includeSystemUsers: includeSystemUsers
    )
  }

  private nonisolated func runTopCommandWithFallback() throws -> String {
    do {
      return try topCommandRunner(
        Self.primaryTopProcessLimit,
        Self.topCommandTimeout
      )
    } catch ProcessSnapshotServiceError.commandTimedOut {
      // A slow primary sample should not make the process section unusable. Retry with enough
      // rows for the visible lists while avoiding another expensive 500-process collection.
      return try topCommandRunner(
        Self.fallbackTopProcessLimit,
        Self.fallbackTopCommandTimeout
      )
    }
  }

  private nonisolated static func runTopCommand(
    processLimit: Int,
    timeout: DispatchTimeInterval
  ) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
    process.arguments = Self.topCommandArguments(processLimit: processLimit)

    let outputPipe = Pipe()
    process.standardOutput = outputPipe

    let errorPipe = Pipe()
    process.standardError = errorPipe

    let outputQueue = DispatchQueue(label: "com.chungxon.memstats.top.stdout")
    let errorQueue = DispatchQueue(label: "com.chungxon.memstats.top.stderr")
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

    if finished.wait(timeout: .now() + timeout) != .success {
      process.terminate()
      // Sampling waits on this call, so never block forever on a `top` that ignores SIGTERM.
      if finished.wait(timeout: .now() + .seconds(1)) != .success {
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
      throw ProcessSnapshotServiceError.commandTimedOut
    }

    // The readers may still be writing the buffers, so never read them before both finish.
    guard readGroup.wait(timeout: .now() + .seconds(1)) == .success else {
      throw ProcessSnapshotServiceError.outputReadTimedOut
    }

    guard process.terminationStatus == 0 else {
      let details =
        String(data: errorData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw ProcessSnapshotServiceError.commandFailed(process.terminationStatus, details)
    }

    guard let output = String(data: outputData, encoding: .utf8) else {
      throw ProcessSnapshotServiceError.utf8DecodeFailed
    }

    return output
  }

  nonisolated static func topCommandArguments(processLimit: Int) -> [String] {
    [
      "-l", "1",
      // Framework memory accounting is not used by the parser and can make top needlessly slow.
      "-F",
      "-o", "mem",
      "-stats", "pid,user,mem,command",
      "-n", String(max(processLimit, 1)),
    ]
  }
}

enum TopProcessSnapshotParser {
  nonisolated static func parse(
    topOutput: String,
    limit: Int? = 8,
    includeRootUser: Bool = true,
    includeSystemUsers: Bool = true
  ) -> [ProcessSnapshot] {
    let parsed =
      topOutput
      .split(whereSeparator: \.isNewline)
      .compactMap(parseLine)
      .filter {
        shouldInclude(
          user: $0.user,
          includeRootUser: includeRootUser,
          includeSystemUsers: includeSystemUsers
        )
      }
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
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let parts = trimmed.split(whereSeparator: \.isWhitespace)
    guard parts.count >= 4 else { return nil }
    guard let pid = Int32(parts[0]) else { return nil }

    let user = String(parts[1])
    guard let rssBytes = parseTopMemoryToken(String(parts[2])) else { return nil }

    let commandParts = parts.dropFirst(3)
    let command = commandParts.joined(separator: " ")
    guard !command.isEmpty else { return nil }

    return ProcessSnapshot(
      user: user,
      pid: pid,
      rssBytes: rssBytes,
      command: command
    )
  }

  nonisolated static func parseTopMemoryToken(_ token: String) -> UInt64? {
    var trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    // `top` appends `+` or `-` when a value changed since the previous sample.
    while let last = trimmed.last, last == "+" || last == "-" {
      trimmed.removeLast()
    }
    guard !trimmed.isEmpty else { return nil }

    let suffix = trimmed.last?.uppercased() ?? ""
    let numericPart: String
    let multiplier: Double

    switch suffix {
    case "B":
      numericPart = String(trimmed.dropLast())
      multiplier = 1
    case "K":
      numericPart = String(trimmed.dropLast())
      multiplier = 1_024
    case "M":
      numericPart = String(trimmed.dropLast())
      multiplier = 1_048_576
    case "G":
      numericPart = String(trimmed.dropLast())
      multiplier = 1_073_741_824
    case "T":
      numericPart = String(trimmed.dropLast())
      multiplier = 1_099_511_627_776
    default:
      numericPart = trimmed
      multiplier = 1
    }

    guard let numericValue = Double(numericPart), numericValue >= 0 else { return nil }
    // Clamp before converting, since `UInt64(_:)` traps on values it cannot represent.
    let bytes = numericValue * multiplier
    guard bytes.isFinite else { return nil }
    return bytes >= Double(UInt64.max) ? UInt64.max : UInt64(bytes)
  }

  nonisolated private static func shouldInclude(
    user: String,
    includeRootUser: Bool,
    includeSystemUsers: Bool
  ) -> Bool {
    if user.isEmpty {
      return false
    }
    if !includeRootUser && user == "root" {
      return false
    }
    if !includeSystemUsers && user.hasPrefix("_") {
      return false
    }
    return true
  }
}

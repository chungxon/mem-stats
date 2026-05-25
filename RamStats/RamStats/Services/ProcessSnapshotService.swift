import Darwin
import Foundation

protocol ProcessSnapshotProviding: Sendable {
  nonisolated func fetchProcesses(includeRootUser: Bool, includeSystemUsers: Bool) throws
    -> [ProcessSnapshot]
  nonisolated func fetchTopProcesses(limit: Int, includeRootUser: Bool, includeSystemUsers: Bool)
    throws -> [ProcessSnapshot]
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
  nonisolated func fetchProcesses(
    includeRootUser: Bool = true,
    includeSystemUsers: Bool = true
  ) throws -> [ProcessSnapshot] {
    let output = try runPSCommand()
    let topMemoryByPID = runTopMemoryByPID()
    let parsed = ProcessSnapshotParser.parse(
      psOutput: output,
      limit: nil,
      includeRootUser: includeRootUser,
      includeSystemUsers: includeSystemUsers
    )
    return applyBestEffortMemoryFootprint(to: parsed, topMemoryByPID: topMemoryByPID)
  }

  nonisolated func fetchTopProcesses(
    limit: Int = 8,
    includeRootUser: Bool = true,
    includeSystemUsers: Bool = true
  ) throws -> [ProcessSnapshot] {
    let output = try runPSCommand()
    let topMemoryByPID = runTopMemoryByPID()
    let parsed = ProcessSnapshotParser.parse(
      psOutput: output,
      limit: nil,
      includeRootUser: includeRootUser,
      includeSystemUsers: includeSystemUsers
    )
    let ranked = applyBestEffortMemoryFootprint(to: parsed, topMemoryByPID: topMemoryByPID)
    return Array(ranked.prefix(max(limit, 0)))
  }

  private nonisolated func runPSCommand() throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "user=,pid=,rss=,command="]

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

  private nonisolated func applyBestEffortMemoryFootprint(
    to snapshots: [ProcessSnapshot],
    topMemoryByPID: [Int32: UInt64]
  ) -> [ProcessSnapshot] {
    snapshots
      .map { snapshot in
        let footprintBytes = memoryFootprintBytes(for: snapshot.pid) ?? 0
        let taskResidentBytes = taskResidentBytes(for: snapshot.pid) ?? 0
        let topMemoryBytes = topMemoryByPID[snapshot.pid] ?? 0
        let bestMemoryBytes = max(
          snapshot.rssBytes,
          footprintBytes,
          taskResidentBytes,
          topMemoryBytes
        )
        return ProcessSnapshot(
          user: snapshot.user,
          pid: snapshot.pid,
          rssBytes: bestMemoryBytes,
          command: snapshot.command
        )
      }
      .sorted { lhs, rhs in
        if lhs.rssBytes == rhs.rssBytes {
          return lhs.pid < rhs.pid
        }
        return lhs.rssBytes > rhs.rssBytes
      }
  }

  private nonisolated func runTopMemoryByPID() -> [Int32: UInt64] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
    process.arguments = ["-l", "1", "-o", "mem", "-stats", "pid,mem", "-n", "200"]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
      finished.signal()
    }

    do {
      try process.run()
    } catch {
      return [:]
    }

    let timeout: DispatchTime = .now() + .seconds(2)
    if finished.wait(timeout: timeout) != .success {
      process.terminate()
      process.waitUntilExit()
      return [:]
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    guard
      process.terminationStatus == 0,
      let output = String(data: outputData, encoding: .utf8)
    else {
      return [:]
    }

    var memoryByPID: [Int32: UInt64] = [:]
    for line in output.split(whereSeparator: \.isNewline) {
      let parts =
        line
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(whereSeparator: \.isWhitespace)
      guard parts.count >= 2 else { continue }
      guard let pid = Int32(parts[0]) else { continue }
      guard let bytes = parseTopMemoryToken(String(parts[1])) else { continue }
      memoryByPID[pid] = bytes
    }

    return memoryByPID
  }

  private nonisolated func parseTopMemoryToken(_ token: String) -> UInt64? {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
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

    guard let numericValue = Double(numericPart), numericValue >= 0 else {
      return nil
    }

    return UInt64(numericValue * multiplier)
  }

  private nonisolated func memoryFootprintBytes(for pid: Int32) -> UInt64? {
    var usage = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &usage) { usagePointer in
      let usageBufferPointer = UnsafeMutableRawPointer(usagePointer)
        .assumingMemoryBound(to: rusage_info_t?.self)
      return proc_pid_rusage(pid, RUSAGE_INFO_V4, usageBufferPointer)
    }

    guard result == 0 else {
      return nil
    }

    return UInt64(usage.ri_phys_footprint)
  }

  private nonisolated func taskResidentBytes(for pid: Int32) -> UInt64? {
    var taskInfo = proc_taskinfo()
    let expectedSize = Int32(MemoryLayout<proc_taskinfo>.stride)

    let result = withUnsafeMutableBytes(of: &taskInfo) { taskInfoBuffer in
      proc_pidinfo(
        pid,
        PROC_PIDTASKINFO,
        0,
        taskInfoBuffer.baseAddress,
        expectedSize
      )
    }

    guard result == expectedSize else {
      return nil
    }

    return UInt64(taskInfo.pti_resident_size)
  }
}

enum ProcessSnapshotParser {
  nonisolated static func parse(
    psOutput: String,
    limit: Int? = 8,
    includeRootUser: Bool = true,
    includeSystemUsers: Bool = true
  ) -> [ProcessSnapshot] {
    let parsed =
      psOutput
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

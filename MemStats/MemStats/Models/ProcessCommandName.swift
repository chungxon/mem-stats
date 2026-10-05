import Foundation

/// Short executable name for a `top` command line, shown in the PROCESS column.
nonisolated enum ProcessCommandName {
  /// The executable's file name, with quotes and backslash escapes handled.
  static func displayName(from command: String) -> String {
    let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedCommand.isEmpty else { return "Unknown" }

    let executableToken = firstCommandToken(from: trimmedCommand) ?? trimmedCommand
    let normalizedExecutableToken = unescapeCommandToken(executableToken)

    guard normalizedExecutableToken.contains("/") else {
      return normalizedExecutableToken
    }

    let executable = URL(fileURLWithPath: normalizedExecutableToken).lastPathComponent
    return executable.isEmpty ? normalizedExecutableToken : executable
  }

  private static func firstCommandToken(from command: String) -> String? {
    var token = ""
    var isInSingleQuote = false
    var isInDoubleQuote = false
    var isEscaped = false

    for character in command {
      if isEscaped {
        token.append(character)
        isEscaped = false
        continue
      }

      if character == "\\" && !isInSingleQuote {
        isEscaped = true
        continue
      }

      if character == "'" && !isInDoubleQuote {
        isInSingleQuote.toggle()
        continue
      }

      if character == "\"" && !isInSingleQuote {
        isInDoubleQuote.toggle()
        continue
      }

      if character.isWhitespace && !isInSingleQuote && !isInDoubleQuote {
        if !token.isEmpty {
          break
        }
        continue
      }

      token.append(character)
    }

    return token.isEmpty ? nil : token
  }

  private static func unescapeCommandToken(_ token: String) -> String {
    token
      .replacingOccurrences(of: "\\ ", with: " ")
      .replacingOccurrences(of: "\\(", with: "(")
      .replacingOccurrences(of: "\\)", with: ")")
      .replacingOccurrences(of: "\\[", with: "[")
      .replacingOccurrences(of: "\\]", with: "]")
  }
}

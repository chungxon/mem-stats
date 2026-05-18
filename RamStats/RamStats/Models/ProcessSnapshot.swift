import Foundation

struct ProcessSnapshot: Sendable, Equatable {
  let user: String
  let pid: Int32
  let rssBytes: UInt64
  let command: String
}

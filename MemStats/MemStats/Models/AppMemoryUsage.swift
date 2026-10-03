import Foundation

struct AppIdentity: Sendable, Hashable {
  let id: String
  let name: String
  let path: String?
}

struct AppMemoryUsage: Identifiable, Sendable, Equatable {
  let id: String
  let name: String
  let path: String?
  let bytes: UInt64
  let processCount: Int
}

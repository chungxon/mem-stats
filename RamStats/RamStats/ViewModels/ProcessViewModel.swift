import Combine
import Foundation

@MainActor
final class ProcessViewModel: ObservableObject {
  @Published private(set) var topProcesses: [ProcessSnapshot] = []
  @Published var selectedUser: String?

  func apply(snapshots: [ProcessSnapshot]) {
    topProcesses = snapshots

    if let selectedUser, !snapshots.contains(where: { $0.user == selectedUser }) {
      self.selectedUser = nil
    }
  }

  var visibleProcesses: [ProcessSnapshot] {
    guard let selectedUser else { return topProcesses }
    return topProcesses.filter { $0.user == selectedUser }
  }
}

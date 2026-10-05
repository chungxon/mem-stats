import Combine
import Foundation
import ServiceManagement

protocol LoginItemRegistrant {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() throws
}

struct MainAppLoginItemRegistrant: LoginItemRegistrant {
  var status: SMAppService.Status {
    SMAppService.mainApp.status
  }

  func register() throws {
    try SMAppService.mainApp.register()
  }

  func unregister() throws {
    try SMAppService.mainApp.unregister()
  }
}

/// Observable so the Settings window and the context menu always show the same state.
final class LoginItemService: ObservableObject {
  private let openAtLoginKey = "openAtLogin"
  private let defaults: UserDefaults
  private let registrant: LoginItemRegistrant

  /// Registered and approved, so the app really opens at login.
  @Published private(set) var isEnabled: Bool
  /// Registered but still waiting for approval in System Settings > Login Items. The toggle
  /// treats this as "on", so the next click cancels it instead of registering again.
  @Published private(set) var requiresApproval = false

  init(
    defaults: UserDefaults = .standard,
    registrant: LoginItemRegistrant = MainAppLoginItemRegistrant()
  ) {
    self.defaults = defaults
    self.registrant = registrant
    self.isEnabled = defaults.bool(forKey: openAtLoginKey)
  }

  func syncWithSystem() {
    let status = registrant.status
    let enabled = status == .enabled
    let pending = status == .requiresApproval
    if isEnabled != enabled {
      isEnabled = enabled
    }
    if requiresApproval != pending {
      requiresApproval = pending
    }
    defaults.set(enabled, forKey: openAtLoginKey)
  }

  /// What the toggle shows as "on": enabled, or registered and waiting for approval.
  var isRequested: Bool {
    isEnabled || requiresApproval
  }

  func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try registrant.register()
    } else {
      try registrant.unregister()
    }

    // `register()` can succeed while the item still needs approval, so trust the system status.
    syncWithSystem()
  }

  /// Registers when off, and unregisters when enabled or pending approval. Returns `isEnabled`.
  @discardableResult
  func toggle() throws -> Bool {
    // The user may have approved or removed the item in System Settings since the last sync.
    syncWithSystem()
    do {
      try setEnabled(!isRequested)
    } catch {
      // Nothing changed, but a SwiftUI toggle already flipped; redraw it from the real state.
      objectWillChange.send()
      throw error
    }
    return isEnabled
  }
}

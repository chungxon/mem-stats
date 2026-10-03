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

final class LoginItemService {
  private let openAtLoginKey = "openAtLogin"
  private let defaults: UserDefaults
  private let registrant: LoginItemRegistrant

  private(set) var isEnabled: Bool

  init(
    defaults: UserDefaults = .standard,
    registrant: LoginItemRegistrant = MainAppLoginItemRegistrant()
  ) {
    self.defaults = defaults
    self.registrant = registrant
    self.isEnabled = defaults.bool(forKey: openAtLoginKey)
  }

  func syncWithSystem() {
    let enabled = registrant.status == .enabled
    isEnabled = enabled
    defaults.set(enabled, forKey: openAtLoginKey)
  }

  /// True when the login item is registered but still waits for user approval in System Settings.
  var requiresApproval: Bool {
    registrant.status == .requiresApproval
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

  @discardableResult
  func toggle() throws -> Bool {
    try setEnabled(!isEnabled)
    return isEnabled
  }
}

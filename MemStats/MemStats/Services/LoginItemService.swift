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

  func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try registrant.register()
    } else {
      try registrant.unregister()
    }

    isEnabled = enabled
    defaults.set(enabled, forKey: openAtLoginKey)
  }

  @discardableResult
  func toggle() throws -> Bool {
    let nextValue = !isEnabled
    try setEnabled(nextValue)
    return nextValue
  }
}

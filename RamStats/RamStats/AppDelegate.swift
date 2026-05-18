import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private let popover = NSPopover()
  private var statusItem: NSStatusItem?
  private let appState = RamStatsAppState()
  private let loginItemService = LoginItemService()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    loginItemService.syncWithSystem()
    configurePopover()
    configureStatusItem()
  }

  private func configurePopover() {
    popover.behavior = .transient
    popover.delegate = self
    popover.contentSize = NSSize(width: 380, height: 540)
    popover.contentViewController = NSHostingController(
      rootView: PopoverRootView(
        appState: appState,
        onOpenActivityMonitor: { [weak self] in
          self?.openActivityMonitor()
        },
        onOpenOptionsMenu: { [weak self] in
          self?.showContextMenuFromPopover()
        }
      )
    )
  }

  private func configureStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    guard let button = item.button else { return }

    button.title = "RAM 0%"
    button.image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "RAM")
    button.imagePosition = .imageLeading
    button.target = self
    button.action = #selector(handleStatusItemClick)
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])

    statusItem = item
  }

  @objc
  private func handleStatusItemClick() {
    guard let button = statusItem?.button else { return }

    let currentEvent = NSApp.currentEvent
    let isOptionClick = currentEvent?.modifierFlags.contains(.option) == true
    let isRightClick = currentEvent?.type == .rightMouseUp

    if isRightClick || isOptionClick {
      showContextMenu(from: button)
      return
    }

    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  private func showContextMenuFromPopover() {
    guard let button = statusItem?.button else { return }
    showContextMenu(from: button)
  }

  private func showContextMenu(from button: NSStatusBarButton) {
    let menu = NSMenu()

    let openAtLogin = NSMenuItem(
      title: "Open at Login",
      action: #selector(toggleOpenAtLogin),
      keyEquivalent: ""
    )
    openAtLogin.target = self
    openAtLogin.state = loginItemService.isEnabled ? .on : .off

    let about = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
    about.target = self

    let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self

    menu.items = [openAtLogin, .separator(), about, quit]
    statusItem?.menu = menu
    button.performClick(nil)
    statusItem?.menu = nil
  }

  @objc
  private func toggleOpenAtLogin(_ sender: NSMenuItem) {
    do {
      let enabled = try loginItemService.toggle()
      sender.state = enabled ? .on : .off
    } catch {
      sender.state = loginItemService.isEnabled ? .on : .off
      presentLoginItemError(error)
    }
  }

  @objc
  private func showAbout() {
    NSApp.orderFrontStandardAboutPanel(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func openActivityMonitor() {
    guard
      let activityMonitorURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.ActivityMonitor"
      )
    else {
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.openApplication(
      at: activityMonitorURL,
      configuration: configuration
    )
  }

  @objc
  private func quitApp() {
    NSApp.terminate(nil)
  }

  private func presentLoginItemError(_ error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Could not update Open at Login"
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  func popoverWillShow(_ notification: Notification) {
    appState.setPopoverPresented(true)
  }

  func popoverDidClose(_ notification: Notification) {
    appState.setPopoverPresented(false)
  }
}

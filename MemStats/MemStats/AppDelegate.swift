import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private let popover = NSPopover()
  private var statusItem: NSStatusItem?
  private let appState = MemStatsAppState()
  private let loginItemService = LoginItemService()
  private var settingsWindow: NSWindow?
  private var cancellables: Set<AnyCancellable> = []
  private var lastDisplayedUsedBytes: UInt64?
  private var lastDisplayedPressureLevel: MemoryPressureLevel?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    loginItemService.syncWithSystem()
    configurePopover()
    configureStatusItem()
    observeMemoryStats()
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

    button.imagePosition = .imageLeading
    button.target = self
    button.action = #selector(handleStatusItemClick)
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    // No sample yet: show a neutral placeholder instead of a green 0%.
    applyStatusAppearance(to: button, usagePercent: nil, pressure: nil)

    statusItem = item
  }

  private func observeMemoryStats() {
    appState.memoryVM.$currentStats
      .compactMap { $0 }
      .sink { [weak self] stats in
        self?.updateStatusItemIfNeeded(with: stats)
      }
      .store(in: &cancellables)
  }

  private func updateStatusItemIfNeeded(with stats: MemoryStats) {
    guard let button = statusItem?.button else { return }

    let shouldUpdate = shouldRefreshStatus(
      currentUsedBytes: stats.usedBytes,
      totalBytes: stats.totalBytes,
      pressureLevel: stats.pressureLevel
    )

    guard shouldUpdate else { return }

    let usagePercent =
      stats.totalBytes > 0
      ? Int((Double(stats.usedBytes) / Double(stats.totalBytes) * 100).rounded())
      : 0
    applyStatusAppearance(to: button, usagePercent: usagePercent, pressure: stats.pressureLevel)

    lastDisplayedUsedBytes = stats.usedBytes
    lastDisplayedPressureLevel = stats.pressureLevel
  }

  /// The menu bar on the active display renders template content and `contentTintColor`
  /// as monochrome, so the pressure color is baked into a non-template image and an
  /// attributed title instead. `nil` values mean no sample has arrived yet.
  private func applyStatusAppearance(
    to button: NSStatusBarButton,
    usagePercent: Int?,
    pressure: MemoryPressureLevel?
  ) {
    let tint = pressure?.color ?? .secondaryLabelColor
    let percentText = usagePercent.map { "\($0)%" } ?? "--%"
    let image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "RAM")?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
    image?.isTemplate = false

    button.contentTintColor = nil
    button.image = image
    button.attributedTitle = NSAttributedString(
      string: "RAM \(percentText)",
      attributes: [
        .foregroundColor: tint,
        // Monospaced digits keep the status item width stable as the percentage changes.
        .font: NSFont.monospacedDigitSystemFont(
          ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
          weight: .regular
        ),
      ]
    )

    // The color alone does not tell VoiceOver or a hover what the pressure is.
    let description: String
    if let usagePercent, let pressure {
      description = "Memory \(usagePercent)%, pressure \(pressure.displayName)"
    } else {
      description = "Memory: waiting for the first sample"
    }
    button.toolTip = description
    button.setAccessibilityLabel(description)
  }

  private func shouldRefreshStatus(
    currentUsedBytes: UInt64,
    totalBytes: UInt64,
    pressureLevel: MemoryPressureLevel
  ) -> Bool {
    if lastDisplayedUsedBytes == nil {
      return true
    }

    if lastDisplayedPressureLevel != pressureLevel {
      return true
    }

    guard let previousUsedBytes = lastDisplayedUsedBytes else {
      return true
    }

    let delta =
      currentUsedBytes > previousUsedBytes
      ? currentUsedBytes - previousUsedBytes
      : previousUsedBytes - currentUsedBytes

    let onePercentThreshold = totalBytes / 100
    let minimumThreshold = UInt64(100 * 1024 * 1024)
    let threshold = max(minimumThreshold, onePercentThreshold)

    return delta >= threshold
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
    // The user can change login items in System Settings while the app runs.
    loginItemService.syncWithSystem()
    openAtLogin.state = loginItemService.isEnabled ? .on : .off

    let showSystemUsers = NSMenuItem(
      title: "Show System Users",
      action: #selector(toggleShowSystemUsers),
      keyEquivalent: ""
    )
    showSystemUsers.target = self
    showSystemUsers.state = appState.showsSystemUsers ? .on : .off
    showSystemUsers.toolTip = "Include root and _* system accounts"

    let settings = NSMenuItem(
      title: "Settings…",
      action: #selector(showSettings),
      keyEquivalent: ","
    )
    settings.target = self

    let about = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
    about.target = self

    let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self

    menu.items = [openAtLogin, showSystemUsers, .separator(), settings, about, quit]
    statusItem?.menu = menu
    button.performClick(nil)
    statusItem?.menu = nil
  }

  /// Shared by the context menu and the Settings window. The menu re-reads the state each
  /// time it opens, and Settings observes `loginItemService`.
  @objc
  private func toggleOpenAtLogin() {
    do {
      try loginItemService.toggle()
      if loginItemService.requiresApproval {
        // Present after the status item menu finishes tracking.
        DispatchQueue.main.async { [weak self] in
          self?.presentLoginItemApprovalPrompt()
        }
      }
    } catch {
      DispatchQueue.main.async { [weak self] in
        self?.presentLoginItemError(error)
      }
    }
  }

  @objc
  private func toggleShowSystemUsers(_ sender: NSMenuItem) {
    appState.setShowsSystemUsers(!appState.showsSystemUsers)
    sender.state = appState.showsSystemUsers ? .on : .off
  }

  /// A self-managed window, since opening a SwiftUI `Settings` scene from an accessory app's
  /// `NSMenu` is not reliable. Reopening reuses the same window.
  @objc
  private func showSettings() {
    loginItemService.syncWithSystem()
    popover.performClose(nil)

    let window = settingsWindow ?? makeSettingsWindow()
    settingsWindow = window
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  private func makeSettingsWindow() -> NSWindow {
    let controller = NSHostingController(
      rootView: SettingsView(
        appState: appState,
        loginItemService: loginItemService,
        onToggleOpenAtLogin: { [weak self] in
          self?.toggleOpenAtLogin()
        }
      )
    )
    controller.sizingOptions = .preferredContentSize

    let window = SettingsWindow(contentViewController: controller)
    window.title = "MemStats Settings"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.center()
    return window
  }

  @objc
  private func showAbout() {
    NSApp.orderFrontStandardAboutPanel(nil)
    NSApp.activate()
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
    NSApp.activate()
    alert.runModal()
  }

  private func presentLoginItemApprovalPrompt() {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Allow MemStats to open at login"
    alert.informativeText =
      "macOS needs your approval. Turn on MemStats in System Settings > General > Login Items."
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Cancel")

    // Accessory apps are not active by default, so bring the alert to the front.
    NSApp.activate()
    if alert.runModal() == .alertFirstButtonReturn {
      SMAppService.openSystemSettingsLoginItems()
    }
  }

  func popoverWillShow(_ notification: Notification) {
    appState.setPopoverPresented(true)
  }

  func popoverDidClose(_ notification: Notification) {
    appState.setPopoverPresented(false)
  }
}

/// The app has no main menu (it is a menu bar accessory), so handle Cmd+W here.
private final class SettingsWindow: NSWindow {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags == .command, event.charactersIgnoringModifiers == "w" {
      performClose(nil)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

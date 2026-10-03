import SwiftUI

struct SettingsView: View {
  @ObservedObject private var settings: SettingsStore
  @ObservedObject private var appState: MemStatsAppState
  @ObservedObject private var loginItemService: LoginItemService

  /// Goes through the same path as the context menu, so approval prompts and errors match.
  private let onToggleOpenAtLogin: () -> Void

  init(
    appState: MemStatsAppState,
    loginItemService: LoginItemService,
    onToggleOpenAtLogin: @escaping () -> Void
  ) {
    self._settings = ObservedObject(wrappedValue: appState.settings)
    self._appState = ObservedObject(wrappedValue: appState)
    self._loginItemService = ObservedObject(wrappedValue: loginItemService)
    self.onToggleOpenAtLogin = onToggleOpenAtLogin
  }

  var body: some View {
    Form {
      Section {
        Picker("Update interval", selection: $settings.memoryInterval) {
          ForEach(SettingsStore.memoryIntervalOptions, id: \.self) { seconds in
            Text(intervalLabel(seconds)).tag(seconds)
          }
        }
        Picker("Update interval for top processes", selection: $settings.processInterval) {
          ForEach(SettingsStore.processIntervalOptions, id: \.self) { seconds in
            Text(intervalLabel(seconds)).tag(seconds)
          }
        }
      } footer: {
        Text(
          "While the popover is closed, both update at most every \(MemStatsAppState.idleMinimumInterval) seconds. Short intervals use more CPU, mostly for top processes."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Section {
        Picker("Number of top apps", selection: $settings.topAppsCount) {
          ForEach(SettingsStore.rowCountOptions, id: \.self) { count in
            Text(verbatim: String(count)).tag(count)
          }
        }
        Picker("Number of top processes", selection: $settings.topProcessesCount) {
          ForEach(SettingsStore.rowCountOptions, id: \.self) { count in
            Text(verbatim: String(count)).tag(count)
          }
        }
      }

      Section {
        Toggle("Open at Login", isOn: openAtLoginBinding)
        Toggle("Show System Users", isOn: showSystemUsersBinding)
          .help("Include root and _* system accounts")
      } footer: {
        if loginItemService.requiresApproval {
          Text(
            "Open at Login needs approval in System Settings > General > Login Items. Turn it off to cancel."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .pickerStyle(.menu)
    .frame(width: 440)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var openAtLoginBinding: Binding<Bool> {
    Binding(
      get: { loginItemService.isRequested },
      set: { _ in onToggleOpenAtLogin() }
    )
  }

  private var showSystemUsersBinding: Binding<Bool> {
    Binding(
      get: { appState.showsSystemUsers },
      set: { appState.setShowsSystemUsers($0) }
    )
  }

  private func intervalLabel(_ seconds: Int) -> String {
    if seconds == 60 {
      return "1 minute"
    }
    return seconds == 1 ? "1 second" : "\(seconds) seconds"
  }
}

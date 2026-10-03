//
//  MemStatsApp.swift
//  MemStats
//
//  Created by Son on 18/5/26.
//

import SwiftUI

@main
struct MemStatsApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  /// The UI lives in the status item, popover and a self-managed Settings window (see
  /// `AppDelegate`). An `App` still needs a scene, so this one is never inserted. It also
  /// leaves out the SwiftUI `Settings` scene, whose Cmd+, would open an empty window.
  var body: some Scene {
    MenuBarExtra("MemStats", systemImage: "memorychip", isInserted: .constant(false)) {
      EmptyView()
    }
  }
}

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

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

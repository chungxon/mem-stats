import Foundation
import SwiftUI

struct PopoverRootView: View {
  @ObservedObject private var appState: RamStatsAppState
  @ObservedObject private var memoryVM: MemoryViewModel
  @ObservedObject private var processVM: ProcessViewModel
  private let onOpenActivityMonitor: () -> Void
  private let onOpenOptionsMenu: () -> Void

  init(
    appState: RamStatsAppState,
    onOpenActivityMonitor: @escaping () -> Void = {},
    onOpenOptionsMenu: @escaping () -> Void = {}
  ) {
    self._appState = ObservedObject(wrappedValue: appState)
    self._memoryVM = ObservedObject(wrappedValue: appState.memoryVM)
    self._processVM = ObservedObject(wrappedValue: appState.processVM)
    self.onOpenActivityMonitor = onOpenActivityMonitor
    self.onOpenOptionsMenu = onOpenOptionsMenu
  }

  private var memoryUsagePercentText: String {
    guard let stats = memoryVM.currentStats, stats.totalBytes > 0 else {
      return "--%"
    }

    let percent = Int((Double(stats.usedBytes) / Double(stats.totalBytes)) * 100)
    return "\(percent)%"
  }

  private var memorySummary: String {
    guard let stats = memoryVM.currentStats else {
      return "Collecting memory data..."
    }

    return "Used \(formatGigabytes(stats.usedBytes)) / \(formatGigabytes(stats.totalBytes))"
  }

  private var swapSummary: String {
    guard let stats = memoryVM.currentStats else {
      return "Swap --"
    }

    return "Swap \(formatGigabytes(stats.swapUsedBytes))"
  }

  private var modeLabel: String {
    switch appState.samplingMode {
    case .active:
      return "Active (5s)"
    case .idle:
      return "Idle (15s)"
    }
  }

  private var processPreview: String {
    guard let process = processVM.topProcesses.first else {
      return "Collecting process data..."
    }
    return "\(process.user) • \(process.command)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Ram Stats")
          .font(.title3.weight(.semibold))
        Spacer()

        Button("Activity Monitor") {
          onOpenActivityMonitor()
        }
        .buttonStyle(.bordered)

        Button("Options") {
          onOpenOptionsMenu()
        }
        .buttonStyle(.bordered)
      }
      .padding(.bottom, 2)

      GroupBox {
        VStack(spacing: 8) {
          Text(memoryUsagePercentText)
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .foregroundStyle(Color.accentColor)
          Text(memorySummary)
            .font(.footnote)
            .foregroundStyle(.secondary)
          Text("Donut chart area (Task 5)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
      } label: {
        Text("RAM by User")
          .font(.headline)
      }
      .background(Color(nsColor: .controlBackgroundColor))

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Sampling")
            Spacer()
            Text(modeLabel)
          }
          .font(.footnote)

          HStack {
            Text("History Samples")
            Spacer()
            Text("\(memoryVM.history.count)")
          }
          .font(.footnote)

          HStack {
            Text("Swap")
            Spacer()
            Text(swapSummary)
          }
          .font(.footnote)

          Text("History chart area (Task 6)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text("History")
          .font(.headline)
      }
      .background(Color(nsColor: .controlBackgroundColor))

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Tracked Processes")
            Spacer()
            Text("\(processVM.topProcesses.count)")
          }
          .font(.footnote)

          Text(processPreview)
            .font(.footnote)
            .lineLimit(1)

          if let lastError = appState.lastSamplingError {
            Text(lastError)
              .font(.footnote)
              .foregroundStyle(.red)
              .lineLimit(2)
          }

          Button("Refresh now") {
            appState.sampleImmediately()
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text("Top Processes")
          .font(.headline)
      }
      .background(Color(nsColor: .controlBackgroundColor))
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func formatGigabytes(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    return String(format: "%.1f GB", gb)
  }
}

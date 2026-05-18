import SwiftUI

struct PopoverRootView: View {
  @ObservedObject private var appState: RamStatsAppState
  @ObservedObject private var memoryVM: MemoryViewModel
  @ObservedObject private var processVM: ProcessViewModel

  init(appState: RamStatsAppState) {
    self._appState = ObservedObject(wrappedValue: appState)
    self._memoryVM = ObservedObject(wrappedValue: appState.memoryVM)
    self._processVM = ObservedObject(wrappedValue: appState.processVM)
  }

  private var memorySummary: String {
    guard let stats = memoryVM.currentStats, stats.totalBytes > 0 else {
      return "Loading memory stats..."
    }

    let percent = Int((Double(stats.usedBytes) / Double(stats.totalBytes)) * 100)
    return "Used \(percent)% of RAM"
  }

  private var modeLabel: String {
    switch appState.samplingMode {
    case .active:
      return "Active (5s)"
    case .idle:
      return "Idle (15s)"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Ram Stats")
          .font(.headline)
        Spacer()
      }

      Divider()

      Text(memorySummary)
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Text("Sampling: \(modeLabel)")
        .font(.footnote)
        .foregroundStyle(.secondary)

      Text("History samples: \(memoryVM.history.count)")
        .font(.footnote)
        .foregroundStyle(.secondary)

      Text("Top processes tracked: \(processVM.topProcesses.count)")
        .font(.footnote)
        .foregroundStyle(.secondary)

      if let lastError = appState.lastSamplingError {
        Text(lastError)
          .font(.footnote)
          .foregroundStyle(.red)
          .lineLimit(2)
      }

      Button("Refresh now") {
        appState.sampleImmediately()
      }
      .buttonStyle(.bordered)

      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

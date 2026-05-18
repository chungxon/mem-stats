import Charts
import Foundation
import SwiftUI

struct PopoverRootView: View {
  @ObservedObject private var appState: RamStatsAppState
  @ObservedObject private var memoryVM: MemoryViewModel
  @ObservedObject private var processVM: ProcessViewModel

  private let onOpenActivityMonitor: () -> Void
  private let onOpenOptionsMenu: () -> Void

  @State private var selectedAngleValue: Double?

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

  private var donutSlices: [DonutSlice] {
    guard let stats = memoryVM.currentStats else { return [] }

    return DonutDataBuilder.buildSlices(
      totalBytes: stats.totalBytes,
      freeBytes: stats.freeBytes,
      snapshots: processVM.topProcesses,
      tinyThreshold: 0.02
    )
  }

  private var activeSelectedSlice: DonutSlice? {
    guard let selectedUser = processVM.selectedUser else { return nil }

    return donutSlices.first {
      if case .user(let user) = $0.category {
        return user == selectedUser
      }
      return false
    }
  }

  private var memorySummary: String {
    guard let stats = memoryVM.currentStats else {
      return "Collecting memory data..."
    }

    return "Used \(formatGigabytes(stats.usedBytes)) / \(formatGigabytes(stats.totalBytes))"
  }

  private var modeLabel: String {
    switch appState.samplingMode {
    case .active:
      return "Active (5s)"
    case .idle:
      return "Idle (15s)"
    }
  }

  private var historyScaleUpperBound: Double {
    if let totalBytes = memoryVM.currentStats?.totalBytes, totalBytes > 0 {
      return Double(totalBytes)
    }

    let maxUsed = memoryVM.history.map(\.usedBytes).max() ?? 1
    return Double(maxUsed)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      headerSection
      donutSection
      historySection
      processSection
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
    .onChange(of: selectedAngleValue) { _, newValue in
      updateSelection(for: newValue)
    }
    .onChange(of: donutSlices.map(\.id)) { _, _ in
      validateSelectionState()
    }
  }

  private var headerSection: some View {
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
  }

  private var donutSection: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        if donutSlices.isEmpty {
          Text("Collecting chart data...")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
        } else {
          Chart(donutSlices) { slice in
            SectorMark(
              angle: .value("Bytes", slice.angleValue),
              innerRadius: .ratio(0.62),
              outerRadius: activeSelectedSlice?.id == slice.id ? .ratio(1.0) : .ratio(0.93),
              angularInset: 1
            )
            .foregroundStyle(color(for: slice))
            .opacity(shouldDim(slice) ? 0.35 : 1)
          }
          .chartLegend(.hidden)
          .chartAngleSelection(value: $selectedAngleValue)
          .frame(height: 170)

          HStack {
            Text(selectionTitle)
              .font(.subheadline.weight(.semibold))
            Spacer()
            Text(selectionSubtitle)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          if processVM.selectedUser != nil {
            Button("Clear Filter") {
              processVM.selectedUser = nil
              selectedAngleValue = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }

        Text(memorySummary)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text("RAM by User")
        .font(.headline)
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var historySection: some View {
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

        if memoryVM.history.isEmpty {
          Text("Collecting history data...")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        } else {
          Chart {
            ForEach(Array(memoryVM.history.enumerated()), id: \.offset) { _, sample in
              LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Used RAM", Double(sample.usedBytes))
              )
              .foregroundStyle(Color.blue)
              .lineStyle(StrokeStyle(lineWidth: 2))
              .interpolationMethod(.monotone)
            }

            ForEach(Array(memoryVM.history.enumerated()), id: \.offset) { _, sample in
              LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Swap Used", Double(sample.swapUsedBytes))
              )
              .foregroundStyle(Color.orange)
              .lineStyle(StrokeStyle(lineWidth: 2))
              .interpolationMethod(.monotone)
            }

            ForEach(Array(memoryVM.history.enumerated()), id: \.offset) { _, sample in
              LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Pressure", scaledPressureValue(for: sample.pressureLevel))
              )
              .foregroundStyle(Color.red)
              .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
              .interpolationMethod(.stepCenter)
            }

            if processVM.selectedUser != nil {
              ForEach(Array(processVM.selectedUserHistory.enumerated()), id: \.offset) {
                _, sample in
                LineMark(
                  x: .value("Time", sample.timestamp),
                  y: .value("Selected User", Double(sample.rssBytes))
                )
                .foregroundStyle(Color.teal)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
              }
            }
          }
          .chartLegend(.hidden)
          .chartYScale(domain: 0...historyScaleUpperBound)
          .chartXAxis(.hidden)
          .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
          }
          .frame(height: 130)

          HStack(spacing: 10) {
            legendItem(color: .blue, label: "Used")
            legendItem(color: .orange, label: "Swap")
            legendItem(color: .red, label: "Pressure")
            if processVM.selectedUser != nil {
              legendItem(color: .teal, label: "Selected")
            }
            Spacer()
          }
          .font(.caption)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text("History")
        .font(.headline)
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var processSection: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(processVM.selectedUser == nil ? "Top Processes" : "Filtered Processes")
            .font(.subheadline.weight(.semibold))
          Spacer()
          Text("\(processVM.visibleProcesses.count)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        if processVM.visibleProcesses.isEmpty {
          Text("No process data")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          ForEach(Array(processVM.visibleProcesses.prefix(5)), id: \.pid) { process in
            HStack(spacing: 8) {
              Text(process.user)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

              Text(process.command)
                .font(.footnote)
                .lineLimit(1)

              Spacer(minLength: 8)

              Text(formatGigabytes(process.rssBytes))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
        }

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

  private var selectionTitle: String {
    guard let slice = activeSelectedSlice else { return "All Users" }
    return slice.label
  }

  private var selectionSubtitle: String {
    guard let slice = activeSelectedSlice else { return "Tap a slice to filter process list" }
    return "\(Int(slice.fractionOfTotal * 100))% of total RAM"
  }

  private func shouldDim(_ slice: DonutSlice) -> Bool {
    guard let selected = activeSelectedSlice else { return false }
    return slice.id != selected.id
  }

  private func updateSelection(for angle: Double?) {
    guard let pickedSlice = DonutDataBuilder.sliceForSelection(angleValue: angle, in: donutSlices)
    else {
      return
    }

    guard case .user(let user) = pickedSlice.category else {
      return
    }

    if processVM.selectedUser == user {
      processVM.selectedUser = nil
      selectedAngleValue = nil
    } else {
      processVM.selectedUser = user
    }
  }

  private func validateSelectionState() {
    guard let selectedUser = processVM.selectedUser else { return }

    let hasMatchingSlice = donutSlices.contains {
      if case .user(let user) = $0.category {
        return user == selectedUser
      }
      return false
    }

    if !hasMatchingSlice {
      processVM.selectedUser = nil
      selectedAngleValue = nil
    }
  }

  private func color(for slice: DonutSlice) -> Color {
    switch slice.category {
    case .free:
      return Color.green
    case .others:
      return Color.gray
    case .user(let user):
      let palette: [Color] = [.blue, .orange, .mint, .indigo, .teal, .cyan, .pink, .brown]
      let index = abs(user.hashValue) % palette.count
      return palette[index]
    }
  }

  private func formatGigabytes(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    return String(format: "%.1f GB", gb)
  }

  private func scaledPressureValue(for level: MemoryPressureLevel) -> Double {
    let base = historyScaleUpperBound

    switch level {
    case .normal:
      return base * 0.25
    case .warning:
      return base * 0.6
    case .critical:
      return base
    }
  }

  @ViewBuilder
  private func legendItem(color: Color, label: String) -> some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 2)
        .fill(color)
        .frame(width: 10, height: 10)
      Text(label)
        .foregroundStyle(.secondary)
    }
  }
}

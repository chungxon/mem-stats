import Charts
import Foundation
import SwiftUI

struct PopoverRootView: View {
  @ObservedObject private var appState: MemStatsAppState
  @ObservedObject private var memoryVM: MemoryViewModel
  @ObservedObject private var processVM: ProcessViewModel

  private let onOpenActivityMonitor: () -> Void
  private let onOpenOptionsMenu: () -> Void

  @State private var hoveredAngleValue: Double?

  init(
    appState: MemStatsAppState,
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
      snapshots: processVM.allProcesses,
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

  private var activeHoveredSlice: DonutSlice? {
    DonutDataBuilder.sliceForSelection(angleValue: hoveredAngleValue, in: donutSlices)
  }

  private var activeFocusSlice: DonutSlice? {
    activeHoveredSlice ?? activeSelectedSlice
  }

  private var orderedMemoryHistory: [MemoryHistorySample] {
    memoryVM.history.sorted { $0.timestamp < $1.timestamp }
  }

  private var orderedSelectedUserHistory: [ProcessViewModel.UserMemoryHistorySample] {
    processVM.selectedUserHistory.sorted { $0.timestamp < $1.timestamp }
  }

  private var memorySummary: String {
    guard let stats = memoryVM.currentStats else {
      return "Loading memory data..."
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
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 14) {
        headerSection
        donutSection
        historySection
        appSection
        processSection
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .onChange(of: donutSlices.map(\.id)) { _, _ in
      validateSelectionState()
      hoveredAngleValue = nil
    }
  }

  private var headerSection: some View {
    HStack {
      Button {
        onOpenActivityMonitor()
      } label: {
        Image(systemName: "waveform.path.ecg")
          .imageScale(.medium)
      }
      .buttonStyle(.plain)
      .help("Open Activity Monitor")
      .accessibilityLabel("Open Activity Monitor")

      Spacer()

      Text("MemStats")
        .font(.title3.weight(.semibold))

      Spacer()

      Button {
        onOpenOptionsMenu()
      } label: {
        Image(systemName: "gearshape")
          .imageScale(.medium)
      }
      .buttonStyle(.plain)
      .help("Open Options")
      .accessibilityLabel("Open Options")
    }
    .padding(.bottom, 2)
  }

  private var donutSection: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        if donutSlices.isEmpty {
          Text("Loading chart data...")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
        } else {
          ZStack {
            Chart(donutSlices) { slice in
              SectorMark(
                angle: .value("Bytes", slice.angleValue),
                innerRadius: .ratio(0.62),
                outerRadius: activeFocusSlice?.id == slice.id ? .ratio(1.0) : .ratio(0.93),
                angularInset: 1
              )
              .foregroundStyle(color(for: slice))
              .opacity(shouldDim(slice) ? 0.35 : 1)
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
              GeometryReader { geometry in
                Color.clear
                  .contentShape(Rectangle())
                  .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                      guard let plotFrame = proxy.plotFrame else {
                        hoveredAngleValue = nil
                        return
                      }
                      hoveredAngleValue = hoverAngleValue(
                        at: location,
                        plotFrame: geometry[plotFrame]
                      )
                    case .ended:
                      hoveredAngleValue = nil
                    }
                  }
                  .gesture(
                    SpatialTapGesture().onEnded { event in
                      guard let plotFrame = proxy.plotFrame else { return }
                      let angle = hoverAngleValue(
                        at: event.location,
                        plotFrame: geometry[plotFrame]
                      )
                      applySelectionToggle(for: angle)
                    }
                  )
              }
            }
            .frame(height: 170)

            donutCenterOverlay
          }

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
      Text("Top Users")
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

        if orderedMemoryHistory.isEmpty {
          Text("Loading history data...")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        } else {
          Chart {
            ForEach(Array(orderedMemoryHistory.enumerated()), id: \.offset) { _, sample in
              AreaMark(
                x: .value("Time", sample.timestamp),
                yStart: .value("Baseline", 0),
                yEnd: .value("Used RAM", Double(sample.usedBytes))
              )
              .foregroundStyle(pressureColor(for: sample.pressureLevel).opacity(0.18))
              .interpolationMethod(.linear)
            }

            ForEach(Array(orderedMemoryHistory.enumerated()), id: \.offset) { _, sample in
              LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Used RAM", Double(sample.usedBytes))
              )
              .foregroundStyle(pressureColor(for: sample.pressureLevel))
              .lineStyle(StrokeStyle(lineWidth: 2))
              .interpolationMethod(.linear)
            }

            if processVM.selectedUser != nil {
              ForEach(Array(orderedSelectedUserHistory.enumerated()), id: \.offset) {
                _, sample in
                LineMark(
                  x: .value("Time", sample.timestamp),
                  y: .value("Selected User", Double(sample.rssBytes))
                )
                .foregroundStyle(.teal)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .interpolationMethod(.linear)
              }
            }
          }
          .chartLegend(.hidden)
          .chartYScale(domain: 0...historyScaleUpperBound)
          .chartXAxis(.hidden)
          .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
              AxisGridLine()
              AxisTick()
              AxisValueLabel {
                if let bytes = value.as(Double.self) {
                  Text(formatBytesAsGigabytes(bytes))
                }
              }
            }
          }
          .frame(height: 130)

          HStack(spacing: 10) {
            if let latestSample = orderedMemoryHistory.last {
              legendItem(color: .blue, label: "Used \(formatGigabytes(latestSample.usedBytes))")
              legendItem(
                color: .orange,
                label: "Swap \(formatGigabytes(latestSample.swapUsedBytes))"
              )
              pressureBadge(level: latestSample.pressureLevel)
            }
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

  private var appSection: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(processVM.selectedUser == nil ? "Top Apps" : "Filtered Apps")
            .font(.subheadline.weight(.semibold))
          Spacer()
          Text("\(processVM.visibleApps.count)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        if processVM.visibleApps.isEmpty {
          Text("No app data available")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          HStack(spacing: 8) {
            Text("APP")
              .frame(maxWidth: .infinity, alignment: .leading)
            Text("PROCS")
              .frame(width: 50, alignment: .trailing)
            Text("MEM")
              .frame(width: 56, alignment: .trailing)
          }
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)

          ForEach(processVM.visibleApps) { app in
            HStack(spacing: 8) {
              Text(app.name)
                .font(.footnote)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(app.path ?? app.name)

              Text(verbatim: String(app.processCount))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)

              Text(formatGigabytes(app.bytes))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text("Top Apps")
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
          Text("No process data available")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          HStack(spacing: 8) {
            Text("USER")
              .frame(width: 58, alignment: .leading)
            Text("PID")
              .frame(width: 50, alignment: .leading)
            Text("PROCESS")
              .frame(maxWidth: .infinity, alignment: .leading)
            Text("MEM")
              .frame(width: 56, alignment: .trailing)
          }
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)

          ForEach(processVM.visibleProcesses, id: \.pid) { process in
            HStack(spacing: 8) {
              Text(process.user)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

              Text(verbatim: String(process.pid))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

              Text(processDisplayName(process.command))
                .font(.footnote)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(process.command)

              Text(formatGigabytes(process.rssBytes))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            }
          }
        }

        if let lastError = appState.lastSamplingError {
          Text(lastError)
            .font(.footnote)
            .foregroundStyle(.red)
            .lineLimit(2)
        }

        Button("Refresh Now") {
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
    guard let slice = activeFocusSlice else { return "All Users" }
    return slice.label
  }

  private var selectionSubtitle: String {
    guard let slice = activeFocusSlice else {
      return "Hover or click a slice to filter the process list"
    }
    return "\(formatGigabytes(slice.bytes)) | \(Int(slice.fractionOfTotal * 100))% of total RAM"
  }

  private func shouldDim(_ slice: DonutSlice) -> Bool {
    guard let focused = activeFocusSlice else { return false }
    return slice.id != focused.id
  }

  private func applySelectionToggle(for angle: Double?) {
    guard
      let angle,
      let pickedSlice = DonutDataBuilder.sliceForSelection(angleValue: angle, in: donutSlices),
      case .user(let user) = pickedSlice.category
    else {
      return
    }

    processVM.selectedUser = processVM.selectedUser == user ? nil : user
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
    }
  }

  private func color(for slice: DonutSlice) -> Color {
    switch slice.category {
    case .free:
      return Color.green
    case .others:
      return Color.gray
    case .unattributed:
      return Color.secondary
    case .user(let user):
      let palette: [Color] = [.blue, .orange, .mint, .indigo, .teal, .cyan, .pink, .brown]
      let index = abs(user.hashValue) % palette.count
      return palette[index]
    }
  }

  private func formatGigabytes(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    return String(format: "%.2f GB", gb)
  }

  private func formatBytesAsGigabytes(_ bytes: Double) -> String {
    let gb = bytes / 1_073_741_824
    if gb == 0 {
      return "0"
    }
    return String(format: "%.2f GB", gb)
  }

  private func processDisplayName(_ command: String) -> String {
    let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedCommand.isEmpty else { return "Unknown" }

    let executableToken = firstCommandToken(from: trimmedCommand) ?? trimmedCommand
    let normalizedExecutableToken = unescapeCommandToken(executableToken)

    guard normalizedExecutableToken.contains("/") else {
      return normalizedExecutableToken
    }

    let executable = URL(fileURLWithPath: normalizedExecutableToken).lastPathComponent
    return executable.isEmpty ? normalizedExecutableToken : executable
  }

  private func firstCommandToken(from command: String) -> String? {
    var token = ""
    var isInSingleQuote = false
    var isInDoubleQuote = false
    var isEscaped = false

    for character in command {
      if isEscaped {
        token.append(character)
        isEscaped = false
        continue
      }

      if character == "\\" && !isInSingleQuote {
        isEscaped = true
        continue
      }

      if character == "'" && !isInDoubleQuote {
        isInSingleQuote.toggle()
        continue
      }

      if character == "\"" && !isInSingleQuote {
        isInDoubleQuote.toggle()
        continue
      }

      if character.isWhitespace && !isInSingleQuote && !isInDoubleQuote {
        if !token.isEmpty {
          break
        }
        continue
      }

      token.append(character)
    }

    return token.isEmpty ? nil : token
  }

  private func unescapeCommandToken(_ token: String) -> String {
    token
      .replacingOccurrences(of: "\\ ", with: " ")
      .replacingOccurrences(of: "\\(", with: "(")
      .replacingOccurrences(of: "\\)", with: ")")
      .replacingOccurrences(of: "\\[", with: "[")
      .replacingOccurrences(of: "\\]", with: "]")
  }

  private var donutCenterOverlay: some View {
    VStack(spacing: 2) {
      Text(donutCenterTitle)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(donutCenterValue)
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .allowsHitTesting(false)
  }

  private var donutCenterTitle: String {
    activeFocusSlice?.label ?? "Used RAM"
  }

  private var donutCenterValue: String {
    guard let stats = memoryVM.currentStats else {
      return "--"
    }

    if let slice = activeFocusSlice {
      return "\(formatGigabytes(slice.bytes)) | \(Int(slice.fractionOfTotal * 100))%"
    }

    let ratio = stats.totalBytes > 0 ? Double(stats.usedBytes) / Double(stats.totalBytes) : 0
    let percent = Int((ratio * 100).rounded())
    return "\(percent)%"
  }

  private func hoverAngleValue(at location: CGPoint, plotFrame: CGRect) -> Double? {
    guard !donutSlices.isEmpty, plotFrame.width > 0, plotFrame.height > 0 else { return nil }

    let center = CGPoint(x: plotFrame.midX, y: plotFrame.midY)
    let dx = location.x - center.x
    let dy = location.y - center.y
    let radius = sqrt((dx * dx) + (dy * dy))
    let maxRadius = min(plotFrame.width, plotFrame.height) / 2
    guard maxRadius > 0 else { return nil }

    let radiusRatio = radius / maxRadius
    guard radiusRatio >= 0.62, radiusRatio <= 1.02 else { return nil }

    var angle = atan2(dx, -dy)
    if angle < 0 {
      angle += (Double.pi * 2)
    }

    let total = donutSlices.reduce(0.0) { $0 + $1.angleValue }
    return (angle / (Double.pi * 2)) * total
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

  @ViewBuilder
  private func pressureBadge(level: MemoryPressureLevel) -> some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 2)
        .fill(pressureColor(for: level))
        .frame(width: 10, height: 10)
      Text("Pressure \(pressureLabel(for: level))")
        .foregroundStyle(.secondary)
    }
  }

  private func pressureColor(for level: MemoryPressureLevel) -> Color {
    switch level {
    case .normal:
      return .green
    case .warning:
      return .orange
    case .critical:
      return .red
    }
  }

  private func pressureLabel(for level: MemoryPressureLevel) -> String {
    switch level {
    case .normal:
      return "Normal"
    case .warning:
      return "Warning"
    case .critical:
      return "Critical"
    }
  }
}

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
    appState.donutSlices
  }

  private var donutUserSlices: [DonutSlice] {
    donutSlices.filter {
      if case .user = $0.category { return true }
      return false
    }
  }

  private var donutAccessibilityValue: String {
    donutSlices
      .map { "\($0.label) \(formatGigabytes($0.bytes)), \(percentText($0.fractionOfTotal))" }
      .joined(separator: "; ")
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

  private var historySegmentPoints: [MemoryHistorySegmentPoint] {
    MemoryHistorySegmentPoint.segments(from: orderedMemoryHistory)
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
    let mode = appState.samplingMode == .active ? "Active" : "Idle"
    let memorySeconds = Int(appState.memorySamplingInterval)
    let processSeconds = Int(appState.processSamplingInterval)
    if memorySeconds == processSeconds {
      return "\(mode) (\(memorySeconds)s)"
    }
    return "\(mode) (\(memorySeconds)s, processes \(processSeconds)s)"
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

          Text(memorySummary)
            .font(.footnote)
            .foregroundStyle(.secondary)
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
          // The hover/tap overlay is mouse only, so expose the slices and the filter to VoiceOver.
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Memory by user")
          .accessibilityValue(donutAccessibilityValue)
          .accessibilityActions {
            ForEach(donutUserSlices) { slice in
              let isSelected = processVM.selectedUser == slice.label
              Button(isSelected ? "Clear filter" : "Filter \(slice.label)") {
                processVM.selectedUser = isSelected ? nil : slice.label
              }
            }
          }

          HStack {
            Text(selectionTitle)
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
            Spacer()
            // Higher priority keeps the numbers whole; a long user name truncates instead.
            Text(selectionSubtitle)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .layoutPriority(1)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      // Overlay keeps the button out of the label's layout, so showing it does not push the box down.
      Text("Top Users")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
          if processVM.selectedUser != nil {
            Button("Clear Filter") {
              processVM.selectedUser = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
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
            ForEach(historySegmentPoints) { point in
              AreaMark(
                x: .value("Time", point.timestamp),
                yStart: .value("Baseline", 0),
                yEnd: .value("Used RAM", Double(point.usedBytes)),
                series: .value("Segment", point.segmentID)
              )
              .foregroundStyle(pressureColor(for: point.pressureLevel).opacity(0.18))
              .interpolationMethod(.linear)
            }

            ForEach(historySegmentPoints) { point in
              LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Used RAM", Double(point.usedBytes)),
                series: .value("Segment", point.segmentID)
              )
              .foregroundStyle(pressureColor(for: point.pressureLevel))
              .lineStyle(StrokeStyle(lineWidth: 2))
              .interpolationMethod(.linear)
            }

            // A single sample has no segment yet, so show it as a point.
            if orderedMemoryHistory.count == 1, let sample = orderedMemoryHistory.first {
              PointMark(
                x: .value("Time", sample.timestamp),
                y: .value("Used RAM", Double(sample.usedBytes))
              )
              .foregroundStyle(pressureColor(for: sample.pressureLevel))
            }

            if processVM.selectedUser != nil {
              // Timestamps are unique and monotonic, so they stay stable as old samples drop.
              ForEach(orderedSelectedUserHistory, id: \.timestamp) { sample in
                LineMark(
                  x: .value("Time", sample.timestamp),
                  y: .value("Selected User", Double(sample.displayBytes)),
                  series: .value("Segment", "selected-user")
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

          // Items wrap one by one, so adding "Selected" only moves that item to the next row.
          LegendFlowLayout(horizontalSpacing: 10, verticalSpacing: 4) {
            legendItems
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .font(.caption)
        }

        // Orange is reserved for the warning pressure level, so hints use the user's color.
        ForEach(appState.growthHints.prefix(2), id: \.user) { hint in
          HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
              .fill(userColor(hint.user))
              .frame(width: 10, height: 10)
            Text(growthHintText(hint))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .font(.caption)
          .help("Possible memory leak hint, based on recent samples")
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
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      sectionLabel(title: "Top Apps", count: processVM.visibleApps.count)
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var processSection: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
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
                .font(.footnote.monospacedDigit())
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
      sectionLabel(title: "Top Processes", count: processVM.visibleProcesses.count)
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var selectionTitle: String {
    guard let slice = activeFocusSlice else { return "All Users" }
    return slice.label
  }

  private var selectionSubtitle: String {
    guard let slice = activeFocusSlice else { return memorySummary }
    guard let stats = memoryVM.currentStats else {
      return "\(formatGigabytes(slice.bytes))"
    }
    // Free memory is not part of used RAM, so it is compared against total RAM instead.
    if case .free = slice.category {
      return "\(formatGigabytes(slice.bytes)) / Total \(formatGigabytes(stats.totalBytes))"
    }
    return "\(formatGigabytes(slice.bytes)) / Used \(formatGigabytes(stats.usedBytes))"
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
      return Color(nsColor: .systemGray)
    case .unattributed:
      return Color(nsColor: Self.unattributedColor)
    case .user(let user):
      return userColor(user)
    }
  }

  /// Opaque lighter gray so it reads differently from the "Others" slice. Resolved per
  /// appearance, since `Color.mix(with:by:)` needs macOS 15.
  private static let unattributedColor = NSColor(name: nil) { appearance in
    var color = NSColor.systemGray
    appearance.performAsCurrentDrawingAppearance {
      color =
        NSColor.systemGray.usingColorSpace(.sRGB)?.blended(withFraction: 0.45, of: .white)
        ?? .systemGray
    }
    return color
  }

  /// Stable per-user color. Green, orange and red are left out so a user never looks like the
  /// "Free" slice or a pressure level.
  private func userColor(_ user: String) -> Color {
    let palette: [Color] = [.blue, .purple, .mint, .indigo, .teal, .cyan, .pink, .brown]
    return palette[DonutDataBuilder.paletteIndex(for: user, paletteCount: palette.count)]
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
      return percentText(slice.fractionOfTotal)
    }

    let ratio = stats.totalBytes > 0 ? Double(stats.usedBytes) / Double(stats.totalBytes) : 0
    return percentText(ratio)
  }

  /// Rounds the same way everywhere, so a slice and the total never disagree by one point.
  private func percentText(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded()))%"
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

  private func growthHintText(_ hint: MemoryGrowthHint) -> String {
    let growth = formatGigabytes(hint.growthBytes)
    switch hint.kind {
    case .suddenJump:
      return "\(hint.user) jumped +\(growth) since the last sample"
    case .continuousGrowth(let samples):
      return "\(hint.user) grew +\(growth) over the last \(samples) samples"
    }
  }

  /// Single section title that also reflects the active user filter.
  private func sectionLabel(title: String, count: Int) -> some View {
    HStack(spacing: 4) {
      Text(title)
        .font(.headline)
      if let selectedUser = processVM.selectedUser {
        Text("· \(selectedUser)")
          .font(.headline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      Text(verbatim: String(count))
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var legendItems: some View {
    if let latestSample = orderedMemoryHistory.last {
      legendItem(
        color: pressureColor(for: latestSample.pressureLevel),
        label: "Used \(formatGigabytes(latestSample.usedBytes))"
      )
      legendItem(
        color: Color(nsColor: .systemGray),
        label: "Swap \(formatGigabytes(latestSample.swapUsedBytes))"
      )
      pressureBadge(level: latestSample.pressureLevel)
    }
    if processVM.selectedUser != nil {
      legendItem(color: .teal, label: "Selected")
    }
  }

  private func legendItem(color: Color, label: String) -> some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 2)
        .fill(color)
        .frame(width: 10, height: 10)
      Text(label)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }
  }

  @ViewBuilder
  private func pressureBadge(level: MemoryPressureLevel) -> some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 2)
        .fill(pressureColor(for: level))
        .frame(width: 10, height: 10)
      Text("Pressure \(level.displayName)")
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }
  }

  private func pressureColor(for level: MemoryPressureLevel) -> Color {
    Color(nsColor: level.color)
  }
}

/// Lays out subviews left to right and starts a new row when the next one does not fit.
private struct LegendFlowLayout: Layout {
  var horizontalSpacing: CGFloat
  var verticalSpacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrangeRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
    let height =
      rows.map(\.height).reduce(0, +)
      + verticalSpacing * CGFloat(max(rows.count - 1, 0))
    // Report the proposed width when there is one, so placeSubviews wraps against the same width.
    if let proposedWidth = proposal.width, proposedWidth.isFinite {
      return CGSize(width: proposedWidth, height: height)
    }
    return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let rows = arrangeRows(maxWidth: bounds.width, subviews: subviews)
    var y = bounds.minY
    for row in rows {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(
          at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
          proposal: ProposedViewSize(size)
        )
        x += size.width + horizontalSpacing
      }
      y += row.height + verticalSpacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrangeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var current = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      if !current.indices.isEmpty, current.width + horizontalSpacing + size.width > maxWidth {
        rows.append(current)
        current = Row()
      }
      current.width += (current.indices.isEmpty ? 0 : horizontalSpacing) + size.width
      current.height = max(current.height, size.height)
      current.indices.append(index)
    }
    if !current.indices.isEmpty {
      rows.append(current)
    }
    return rows
  }
}

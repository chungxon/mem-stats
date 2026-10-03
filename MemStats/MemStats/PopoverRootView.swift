import Charts
import Foundation
import SwiftUI

struct PopoverRootView: View {
  /// Matches `NSPopover.contentSize` in `AppDelegate`.
  static let popoverSize = CGSize(width: 380, height: 540)

  @ObservedObject private var appState: MemStatsAppState
  @ObservedObject private var memoryVM: MemoryViewModel
  @ObservedObject private var processVM: ProcessViewModel

  private let onOpenActivityMonitor: () -> Void
  private let onOpenOptionsMenu: () -> Void

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

  private var modeLabel: String {
    let mode = appState.samplingMode == .active ? "Active" : "Idle"
    let memorySeconds = Int(appState.memorySamplingInterval)
    let processSeconds = Int(appState.processSamplingInterval)
    if memorySeconds == processSeconds {
      return "\(mode) (\(memorySeconds)s)"
    }
    return "\(mode) (\(memorySeconds)s, processes \(processSeconds)s)"
  }

  private var historyAccessibilityValue: String {
    guard let latest = memoryVM.history.last else { return "No samples" }
    var parts = [
      "Used \(MemoryFormat.size(latest.usedBytes))",
      "pressure \(latest.pressureLevel.displayName)",
      "swap \(MemoryFormat.size(latest.swapUsedBytes))",
    ]
    if let total = memoryVM.currentStats?.totalBytes {
      parts[0] += " of \(MemoryFormat.size(total))"
    }
    if let selectedUser = processVM.selectedUser,
      let selected = processVM.selectedUserHistory.last
    {
      parts.append("\(selectedUser) \(MemoryFormat.size(selected.displayBytes))")
    }
    parts.append("\(memoryVM.history.count) samples")
    return parts.joined(separator: ", ")
  }

  /// "Loading…" until the first process sample lands or fails (the error shows below).
  private func listPlaceholder(empty: String) -> String {
    appState.isWaitingForFirstProcessSample ? "Loading…" : empty
  }

  private var historyScaleUpperBound: Double {
    if let totalBytes = memoryVM.currentStats?.totalBytes, totalBytes > 0 {
      return Double(totalBytes)
    }

    let maxUsed = memoryVM.history.map(\.usedBytes).max() ?? 1
    return Double(maxUsed)
  }

  var body: some View {
    // The header stays outside the scroll view so its buttons are always reachable.
    VStack(spacing: 0) {
      headerSection
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

      Divider()

      ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 14) {
          DonutSectionView(
            slices: appState.donutSlices,
            stats: memoryVM.currentStats,
            selectedUser: processVM.selectedUser,
            onSelectUser: { processVM.selectedUser = $0 }
          )
          historySection
          appSection
          processSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
    .frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var headerSection: some View {
    HStack {
      Button {
        onOpenActivityMonitor()
      } label: {
        Image(systemName: "waveform.path.ecg")
          .imageScale(.medium)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
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
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Open Options")
      .accessibilityLabel("Open Options")
    }
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
          Text("Loading history data...")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        } else {
          Chart {
            ForEach(memoryVM.historySegments) { point in
              AreaMark(
                x: .value("Time", point.timestamp),
                yStart: .value("Baseline", 0),
                yEnd: .value("Used RAM", Double(point.usedBytes)),
                series: .value("Segment", point.segmentID)
              )
              .foregroundStyle(PopoverStyle.pressureColor(point.pressureLevel).opacity(0.18))
              .interpolationMethod(.linear)
            }

            ForEach(memoryVM.historySegments) { point in
              LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Used RAM", Double(point.usedBytes)),
                series: .value("Segment", point.segmentID)
              )
              .foregroundStyle(PopoverStyle.pressureColor(point.pressureLevel))
              .lineStyle(StrokeStyle(lineWidth: 2))
              .interpolationMethod(.linear)
            }

            // A single sample has no segment yet, so show it as a point.
            if memoryVM.history.count == 1, let sample = memoryVM.history.first {
              PointMark(
                x: .value("Time", sample.timestamp),
                y: .value("Used RAM", Double(sample.usedBytes))
              )
              .foregroundStyle(PopoverStyle.pressureColor(sample.pressureLevel))
            }

            if processVM.selectedUser != nil {
              // Timestamps are unique and monotonic, so they stay stable as old samples drop.
              ForEach(processVM.selectedUserHistory, id: \.timestamp) { sample in
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
            AxisMarks(
              position: .leading,
              values: MemoryFormat.axisTickValues(upperBound: historyScaleUpperBound)
            ) { value in
              AxisGridLine()
              AxisTick()
              AxisValueLabel {
                if let bytes = value.as(Double.self) {
                  Text(MemoryFormat.axisTick(bytes))
                }
              }
            }
          }
          .frame(height: 130)
          // Hundreds of marks are noise for VoiceOver, so read the chart as one summary.
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Memory history")
          .accessibilityValue(historyAccessibilityValue)

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
              .fill(PopoverStyle.userColor(hint.user))
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
          Text(listPlaceholder(empty: "No app data available"))
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          HStack(spacing: 8) {
            Text("APP")
              .frame(maxWidth: .infinity, alignment: .leading)
            Text("PROCS")
              .frame(width: 50, alignment: .trailing)
            Text("MEM")
              .frame(width: 64, alignment: .trailing)
          }
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(.isHeader)

          ForEach(processVM.visibleApps) { app in
            HStack(spacing: 8) {
              Text(app.name)
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(app.path ?? app.name)

              Text(verbatim: String(app.processCount))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)

              Text(MemoryFormat.size(app.bytes))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            }
            // One VoiceOver element per row, with the column names spoken.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
              "\(app.name), \(app.processCount) \(app.processCount == 1 ? "process" : "processes"), \(MemoryFormat.size(app.bytes))"
            )
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
          Text(listPlaceholder(empty: "No process data available"))
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
              .frame(width: 64, alignment: .trailing)
          }
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(.isHeader)

          ForEach(processVM.visibleProcesses, id: \.pid) { process in
            HStack(spacing: 8) {
              Text(process.user)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 58, alignment: .leading)
                .help(process.user)

              Text(verbatim: String(process.pid))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

              Text(processVM.displayName(for: process))
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(process.command)

              Text(MemoryFormat.size(process.rssBytes))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
              "\(processVM.displayName(for: process)), user \(process.user), PID \(process.pid), \(MemoryFormat.size(process.rssBytes))"
            )
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

  private func growthHintText(_ hint: MemoryGrowthHint) -> String {
    let growth = MemoryFormat.size(hint.growthBytes)
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
    if let latestSample = memoryVM.history.last {
      legendItem(
        color: PopoverStyle.pressureColor(latestSample.pressureLevel),
        label: "Used \(MemoryFormat.size(latestSample.usedBytes))"
      )
      legendItem(
        color: Color(nsColor: .systemGray),
        label: "Swap \(MemoryFormat.size(latestSample.swapUsedBytes))"
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
        .fill(PopoverStyle.pressureColor(level))
        .frame(width: 10, height: 10)
      Text("Pressure \(level.displayName)")
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }
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

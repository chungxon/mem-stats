import Charts
import SwiftUI

/// The "Top Users" donut. Hover state lives here, so moving the mouse over the chart only
/// redraws this section, and only when the hovered slice changes.
struct DonutSectionView: View {
  let slices: [DonutSlice]
  let stats: MemoryStats?
  let selectedUser: String?
  let language: AppLanguage
  let glassBackgroundEnabled: Bool
  let glassOpacity: Double
  let onSelectUser: (String?) -> Void

  @State private var hoveredSliceID: DonutSlice.ID?

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        if slices.isEmpty {
          Text("Loading chart data…")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)

          Text(memorySummary)
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          ZStack {
            chart
              .frame(height: 170)

            centerOverlay
          }
          // The hover/tap overlay is mouse only, so expose the slices and the filter to VoiceOver.
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Memory by user")
          .accessibilityValue(accessibilityValue)
          .accessibilityActions {
            ForEach(userSlices) { slice in
              let isSelected = selectedUser == slice.label
              Button {
                onSelectUser(isSelected ? nil : slice.label)
              } label: {
                Text(
                  verbatim: isSelected
                    ? AppLocalization.string("Clear filter", language: language)
                    : AppLocalization.formatted(
                      "Filter %@", language: language, slice.label
                    ))
              }
            }
          }

          HStack {
            Text(focusSlice?.label ?? AppLocalization.string("All Users", language: language))
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
            Spacer()
            // Higher priority keeps the numbers whole; a long user name truncates instead.
            Text(selectionSubtitle)
              .font(.footnote.monospacedDigit())
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
          if selectedUser != nil {
            Button("Clear Filter") {
              onSelectUser(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
    }
    .background(
      GlassSurfaceStyle.sectionColor(
        glassEnabled: glassBackgroundEnabled,
        opacity: glassOpacity
      )
    )
    .onChange(of: slices.map(\.id)) { _, _ in
      validateSelection()
      hoveredSliceID = nil
    }
  }

  private var chart: some View {
    Chart(slices) { slice in
      SectorMark(
        angle: .value("Bytes", slice.angleValue),
        innerRadius: .ratio(0.62),
        outerRadius: focusSlice?.id == slice.id ? .ratio(1.0) : .ratio(0.93),
        angularInset: 1
      )
      .foregroundStyle(PopoverStyle.sliceColor(slice))
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
                setHoveredSlice(nil)
                return
              }
              let angle = angleValue(at: location, plotFrame: geometry[plotFrame])
              setHoveredSlice(DonutDataBuilder.sliceForSelection(angleValue: angle, in: slices))
            case .ended:
              setHoveredSlice(nil)
            }
          }
          .gesture(
            SpatialTapGesture().onEnded { event in
              guard let plotFrame = proxy.plotFrame else { return }
              let angle = angleValue(at: event.location, plotFrame: geometry[plotFrame])
              toggleSelection(at: angle)
            }
          )
      }
    }
  }

  private var centerOverlay: some View {
    VStack(spacing: 2) {
      Text(focusSlice?.label ?? AppLocalization.string("Used RAM", language: language))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(centerValue)
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(
      GlassSurfaceStyle.centerOverlayColor(
        glassEnabled: glassBackgroundEnabled,
        opacity: glassOpacity
      )
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .allowsHitTesting(false)
  }

  private var userSlices: [DonutSlice] {
    slices.filter {
      if case .user = $0.category { return true }
      return false
    }
  }

  private var selectedSlice: DonutSlice? {
    guard let selectedUser else { return nil }
    return slices.first {
      if case .user(let user) = $0.category { return user == selectedUser }
      return false
    }
  }

  private var focusSlice: DonutSlice? {
    if let hoveredSliceID, let hovered = slices.first(where: { $0.id == hoveredSliceID }) {
      return hovered
    }
    return selectedSlice
  }

  private var memorySummary: String {
    guard let stats else {
      return AppLocalization.string("Loading memory data…", language: language)
    }
    return AppLocalization.formatted(
      "Used %@ / %@",
      language: language,
      MemoryFormat.size(stats.usedBytes),
      MemoryFormat.size(stats.totalBytes)
    )
  }

  private var selectionSubtitle: String {
    guard let slice = focusSlice else { return memorySummary }
    guard let stats else { return MemoryFormat.size(slice.bytes) }
    // Free memory is not part of used RAM, so it is compared against total RAM instead.
    if case .free = slice.category {
      return AppLocalization.formatted(
        "%@ / Total %@",
        language: language,
        MemoryFormat.size(slice.bytes),
        MemoryFormat.size(stats.totalBytes)
      )
    }
    return AppLocalization.formatted(
      "%@ / Used %@",
      language: language,
      MemoryFormat.size(slice.bytes),
      MemoryFormat.size(stats.usedBytes)
    )
  }

  private var centerValue: String {
    guard let stats else { return "--" }
    if let slice = focusSlice {
      return PopoverStyle.percentText(slice.fractionOfTotal)
    }
    let ratio = stats.totalBytes > 0 ? Double(stats.usedBytes) / Double(stats.totalBytes) : 0
    return PopoverStyle.percentText(ratio)
  }

  private var accessibilityValue: String {
    slices
      .map {
        AppLocalization.formatted(
          "%@ %@, %@",
          language: language,
          $0.label,
          MemoryFormat.size($0.bytes),
          PopoverStyle.percentText($0.fractionOfTotal)
        )
      }
      .joined(separator: "; ")
  }

  private func shouldDim(_ slice: DonutSlice) -> Bool {
    guard let focused = focusSlice else { return false }
    return slice.id != focused.id
  }

  /// Writes state only when the hovered slice changes, not on every mouse move.
  private func setHoveredSlice(_ slice: DonutSlice?) {
    if hoveredSliceID != slice?.id {
      hoveredSliceID = slice?.id
    }
  }

  private func toggleSelection(at angle: Double?) {
    guard
      let pickedSlice = DonutDataBuilder.sliceForSelection(angleValue: angle, in: slices),
      case .user(let user) = pickedSlice.category
    else {
      return
    }
    onSelectUser(selectedUser == user ? nil : user)
  }

  private func validateSelection() {
    if selectedUser != nil, selectedSlice == nil {
      onSelectUser(nil)
    }
  }

  private func angleValue(at location: CGPoint, plotFrame: CGRect) -> Double? {
    guard !slices.isEmpty, plotFrame.width > 0, plotFrame.height > 0 else { return nil }

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

    let total = slices.reduce(0.0) { $0 + $1.angleValue }
    return (angle / (Double.pi * 2)) * total
  }
}

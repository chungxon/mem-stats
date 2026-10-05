import AppKit
import Combine
import SwiftUI

enum GlassBackgroundResolver {
  static func shouldUseGlass(preferenceEnabled: Bool, reduceTransparency: Bool) -> Bool {
    preferenceEnabled && !reduceTransparency
  }
}

final class AccessibilityDisplaySettings: ObservableObject {
  @Published private(set) var shouldReduceTransparency =
    NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

  private var accessibilityObserver: NSObjectProtocol?

  init() {
    accessibilityObserver = NotificationCenter.default.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.shouldReduceTransparency =
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
  }

  deinit {
    if let accessibilityObserver {
      NotificationCenter.default.removeObserver(accessibilityObserver)
    }
  }
}

enum GlassSettingsObservation {
  static func observe(
    _ settings: SettingsStore,
    onChange: @escaping (Bool, Double) -> Void
  ) -> AnyCancellable {
    settings.$glassBackground
      .removeDuplicates()
      .combineLatest(settings.$glassOpacity.removeDuplicates())
      .sink { values in
        // @Published sends before the stored property changes. Never read it again here.
        onChange(values.0, values.1)
      }
  }
}

enum GlassSurfaceStyle {
  // AppKit owns the blur radius. Blend a little unblurred backdrop through the material.
  static let materialAlpha: CGFloat = 1.0

  static func effectiveOpacity(_ opacity: Double) -> Double {
    min(max(opacity, 0), 1) * 0.8
  }

  static func sectionColor(glassEnabled: Bool, opacity: Double) -> Color {
    Color(nsColor: .controlBackgroundColor)
      .opacity(glassEnabled ? effectiveOpacity(opacity) : 1)
  }

  static func centerOverlayColor(glassEnabled: Bool, opacity: Double) -> Color {
    Color(nsColor: .windowBackgroundColor)
      .opacity(glassEnabled ? min(opacity + 0.16, 0.95) : 1)
  }
}

final class GlassBackgroundContainerView: NSView {
  private let visualEffectView = NSVisualEffectView()
  private let tintView = NSView()
  private var accessibilityObserver: NSObjectProtocol?

  var material: NSVisualEffectView.Material = .sidebar {
    didSet { visualEffectView.material = material }
  }

  var popoverArrowHeight: CGFloat = 0 {
    didSet { needsLayout = true }
  }

  var preferenceEnabled = false {
    didSet {
      updateBackground()
    }
  }

  var glassOpacity = SettingsStore.defaultGlassOpacity {
    didSet {
      updateBackground()
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    wantsLayer = true
    visualEffectView.translatesAutoresizingMaskIntoConstraints = false
    visualEffectView.material = material
    visualEffectView.blendingMode = .behindWindow
    visualEffectView.state = .active
    addSubview(visualEffectView)
    tintView.wantsLayer = true
    tintView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(tintView)
    NSLayoutConstraint.activate([
      visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
      visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
      visualEffectView.topAnchor.constraint(equalTo: topAnchor),
      visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
      tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tintView.topAnchor.constraint(equalTo: topAnchor),
      tintView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    accessibilityObserver = NotificationCenter.default.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.updateBackground()
    }
    updateBackground()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    stopObservingAccessibilityChanges()
  }

  override func layout() {
    super.layout()
    guard popoverArrowHeight > 0 else {
      layer?.mask = nil
      return
    }

    let body = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - popoverArrowHeight)
    let outline = CGMutablePath()
    outline.addRoundedRect(in: body, cornerWidth: 14, cornerHeight: 14)
    let center = bounds.midX
    outline.move(to: CGPoint(x: center - 10, y: body.maxY))
    outline.addLine(to: CGPoint(x: center, y: bounds.maxY))
    outline.addLine(to: CGPoint(x: center + 10, y: body.maxY))
    outline.closeSubpath()
    let mask = CAShapeLayer()
    mask.path = outline
    layer?.mask = mask
  }

  private func stopObservingAccessibilityChanges() {
    if let accessibilityObserver {
      NotificationCenter.default.removeObserver(accessibilityObserver)
      self.accessibilityObserver = nil
    }
  }

  private func updateBackground() {
    let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    let useGlass = GlassBackgroundResolver.shouldUseGlass(
      preferenceEnabled: preferenceEnabled,
      reduceTransparency: reduceTransparency
    )

    visualEffectView.isHidden = !useGlass
    visualEffectView.alphaValue = useGlass ? GlassSurfaceStyle.materialAlpha : 1
    tintView.isHidden = !useGlass
    // The slider adjusts the tint, independently of the material blend.
    let opacity = GlassSurfaceStyle.effectiveOpacity(glassOpacity)
    tintView.layer?.backgroundColor =
      NSColor.windowBackgroundColor
      .withAlphaComponent(opacity).cgColor
    layer?.backgroundColor = (useGlass ? NSColor.clear : NSColor.windowBackgroundColor).cgColor
  }
}

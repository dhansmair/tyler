import AppKit
import TylerCore
import TylerServer

/// The real `LayoutNotice`: a borderless panel that takes no focus and lets clicks through, with
/// a see-through blur behind the name. Pointer checks skip it as one of tylerd's own
/// windows (`MacWindowStacking`).
@MainActor
package final class MacLayoutNotice: LayoutNotice {
  private static let hold = Duration.milliseconds(500)
  private static let fade = 0.25
  private static let height: CGFloat = 96
  private static let minimumWidth: CGFloat = 200
  private static let sideMargin: CGFloat = 36

  private let panel: NSPanel
  private let label = NSTextField(labelWithString: "")
  private var hiding: Task<Void, Never>?

  package init() {
    panel = NSPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: true)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
    ]
    label.font = .systemFont(ofSize: 30, weight: .semibold)
    label.textColor = .labelColor
    panel.contentView = Background(around: Self.centring(label))
  }

  package func show(_ name: String, in area: CGRect) {
    hiding?.cancel()
    label.stringValue = name
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    // The flip between Accessibility and AppKit coordinates is its own inverse.
    let visible = DisplayGeometry.axRect(fromAppKit: area, primaryScreenHeight: primaryHeight)
    let width = max(Self.minimumWidth, label.intrinsicContentSize.width + 2 * Self.sideMargin)
    let origin = CGPoint(x: visible.midX - width / 2, y: visible.midY - Self.height / 2)
    panel.setFrame(
      CGRect(origin: origin, size: CGSize(width: width, height: Self.height)), display: true)
    // Through the animator: it replaces a fade under way, which a plain assignment would not stop.
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      panel.animator().alphaValue = 1
    }
    panel.orderFrontRegardless()
    hiding = Task { [weak self] in
      do {
        try await Task.sleep(for: Self.hold)
      } catch {
        return
      }
      await self?.fadeOut()
    }
  }

  private func fadeOut() async {
    await NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fade
      panel.animator().alphaValue = 0
    }
    guard !Task.isCancelled else { return }
    panel.orderOut(nil)
  }

  private static func centring(_ label: NSTextField) -> NSView {
    let content = NSView()
    label.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
    ])
    return content
  }

  /// The HUD blur, half see-through so that what lies behind shows, with a bright edge and a
  /// highlight along the top. The two layers drawn over the blur follow the view's size here:
  /// nothing lays out a view's extra layers.
  private final class Background: NSView {
    private static let cornerRadius: CGFloat = 24
    private let highlight = CAGradientLayer()
    private let edge = CALayer()

    init(around content: NSView) {
      super.init(frame: .zero)
      wantsLayer = true
      layer?.cornerRadius = Self.cornerRadius
      layer?.masksToBounds = true

      let blur = NSVisualEffectView()
      blur.material = .hudWindow
      blur.blendingMode = .behindWindow
      blur.state = .active
      blur.alphaValue = 0.5
      fill(with: blur)

      highlight.colors = [
        NSColor.white.withAlphaComponent(0.22).cgColor,
        NSColor.white.withAlphaComponent(0).cgColor,
      ]
      highlight.startPoint = CGPoint(x: 0.5, y: 1)
      highlight.endPoint = CGPoint(x: 0.5, y: 0.45)
      layer?.addSublayer(highlight)

      edge.cornerRadius = Self.cornerRadius
      edge.borderWidth = 1
      edge.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
      layer?.addSublayer(edge)

      fill(with: content)
      content.wantsLayer = true
      content.layer?.zPosition = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
      super.layout()
      highlight.frame = bounds
      edge.frame = bounds
    }

    private func fill(with view: NSView) {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: leadingAnchor),
        view.trailingAnchor.constraint(equalTo: trailingAnchor),
        view.topAnchor.constraint(equalTo: topAnchor),
        view.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }
  }
}

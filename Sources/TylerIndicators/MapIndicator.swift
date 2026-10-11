import AppKit
import TylerCore

/// The map menu bar item: a thumbnail of every workspace with its windows, as `WorkspaceMap`
/// lays them out: the current workspace's windows bright and the others' dimmed, the focused
/// window filled in a light accent colour. A left click on a thumbnail switches to that workspace;
/// a right click or ctrl-click opens the same menu as the text item. Hidden while tiling isn't
/// running, and when `[indicator] map = false`.
@MainActor
public final class MapIndicator: NSObject, Indicator {
  private static let cornerRadius: CGFloat = 2

  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let perform: @MainActor (Request) -> Void
  private let menuBuilder: MenuBuilder
  /// What the item shows now (`nil` while hidden), so it is only redrawn when that changes.
  private var map: WorkspaceMap?
  /// Until the first `show`, the item shows nothing yet but is visible.
  private var hasShown = false
  private let iconCache = IconCache()
  /// The menu a right click opens, kept up to date but only built when it opens.
  private var menu: IndicatorMenu?

  public init(perform: @escaping @MainActor (Request) -> Void) {
    self.perform = perform
    menuBuilder = MenuBuilder(perform: perform)
    super.init()
    // No `item.menu`: an item with a menu opens it on every click and never sends the action.
    item.button?.target = self
    item.button?.action = #selector(click(_:))
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  public func show(_ snapshot: IndicatorSnapshot) {
    menu = IndicatorMenu(snapshot)
    // As high as the status item's button allows (22 points; the menu bar around it is out of
    // reach).
    let map = WorkspaceMap(snapshot, height: NSStatusBar.system.thickness)
    guard !hasShown || map != self.map else { return }
    hasShown = true
    self.map = map
    item.isVisible = map != nil
    if let map {
      item.button?.image = Self.image(for: map, icons: iconCache.icons(for: map))
    }
  }

  @objc private func click(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }
    if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
      openMenu()
      return
    }
    // The image is centred in the button.
    guard let map, let image = sender.image else { return }
    let point = sender.convert(event.locationInWindow, from: nil)
    let left = (sender.bounds.width - image.size.width) / 2
    guard let index = map.workspaceIndex(at: CGPoint(x: point.x - left, y: 0)) else { return }
    perform(.workspace(.number(index + 1)))
  }

  /// Pops the shared menu up under the item, the way an item with a menu opens it.
  private func openMenu() {
    guard let menu, let button = item.button else { return }
    item.menu = menuBuilder.menu(for: menu)
    button.performClick(nil)
    item.menu = nil
  }

  /// The focused window's fill: the accent colour (blue unless changed in System Settings),
  /// lightened. Blended here, while the image draws, so it follows the appearance and accent.
  private static var focusColor: NSColor {
    NSColor.controlAccentColor.blended(withFraction: 0.4, of: .white) ?? .controlAccentColor
  }

  /// The map as an image. Not a template image, so the accent colour and the app icons survive;
  /// the colours are dynamic and resolve against the menu bar's appearance each time the image
  /// is drawn.
  private static func image(for map: WorkspaceMap, icons: MapIcons) -> NSImage {
    NSImage(size: map.size, flipped: true) { _ in
      for thumbnail in map.thumbnails {
        draw(thumbnail, icons: icons)
      }
      return true
    }
  }

  /// The current workspace stands out by brightness, with no outline, so the thumbnails can
  /// take the button's full height: its windows are bright and the others' dimmed, and its slot
  /// is a little brighter, which marks it when it is empty. Each window shows its app's icon,
  /// dimmed like the window on other workspaces, or the SF Symbol or glyph set for the app, cut
  /// out of the window so it reads in light and dark menu bars alike.
  private static func draw(_ thumbnail: WorkspaceMap.Thumbnail, icons: MapIcons) {
    let slotColor: NSColor = thumbnail.isCurrent ? .tertiaryLabelColor : .quaternaryLabelColor
    let windowColor: NSColor = thumbnail.isCurrent ? .labelColor : .secondaryLabelColor
    slotColor.setFill()
    NSBezierPath(roundedRect: thumbnail.frame, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    for index in thumbnail.drawingOrder {
      let window = thumbnail.windows[index]
      (index == thumbnail.focusedIndex ? focusColor : windowColor).setFill()
      window.frame.fill()
      guard let iconFrame = window.iconFrame,
        !drawCustomIcon(window.customIcon, in: iconFrame, icons: icons),
        let icon = window.processID.flatMap({ icons.apps[$0] })
      else { continue }
      icon.draw(
        in: iconFrame, from: .zero, operation: .sourceOver,
        fraction: thumbnail.isCurrent ? 1 : 0.5, respectFlipped: true, hints: nil)
    }
  }

  /// Cuts the SF Symbol or glyph set for a window's app out of the window. Returns false if
  /// there is none, or it wasn't found, so the app's icon shows instead.
  private static func drawCustomIcon(
    _ icon: IndicatorIcon?, in frame: CGRect, icons: MapIcons
  ) -> Bool {
    switch icon {
    case .symbol(let name):
      guard let symbol = icons.symbols[name] else { return false }
      symbol.draw(
        in: aspectFit(symbol.size, in: frame), from: .zero, operation: .destinationOut,
        fraction: 1, respectFlipped: true, hints: nil)
    case .glyph(let character):
      guard let outline = icons.glyphs[character],
        let context = NSGraphicsContext.current?.cgContext
      else { return false }
      // The outline is y up; the map is drawn y down, so it is flipped as it is fitted.
      let bounds = outline.boundingBoxOfPath
      let fitted = aspectFit(bounds.size, in: frame)
      let scale = fitted.width / bounds.width
      var transform = CGAffineTransform(
        a: scale, b: 0, c: 0, d: -scale, tx: fitted.minX - bounds.minX * scale,
        ty: fitted.maxY + bounds.minY * scale)
      guard let placed = outline.copy(using: &transform) else { return false }
      context.saveGState()
      context.setBlendMode(.destinationOut)
      context.addPath(placed)
      context.fillPath()
      context.restoreGState()
    case nil:
      return false
    }
    return true
  }

  /// `size` scaled to fit in `frame`, keeping its shape, and centred there.
  private static func aspectFit(_ size: CGSize, in frame: CGRect) -> CGRect {
    guard size.width > 0, size.height > 0 else { return frame }
    let scale = min(frame.width / size.width, frame.height / size.height)
    let fitted = CGSize(width: size.width * scale, height: size.height * scale)
    return CGRect(
      x: frame.midX - fitted.width / 2, y: frame.midY - fitted.height / 2,
      width: fitted.width, height: fitted.height)
  }
}

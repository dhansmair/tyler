import AppKit
import TylerCore

/// The map menu bar item: a thumbnail of every workspace with its windows, as `WorkspaceMap`
/// lays them out, the current workspace outlined and the focused window bordered in the accent
/// colour. A left click on a thumbnail switches to that workspace; a right click or ctrl-click
/// opens the same menu as the text item. Hidden while tiling isn't running, and when
/// `[indicator] map = false`.
@MainActor
public final class MapIndicator: NSObject, Indicator {
  /// Room around the map for the current workspace's outline, which sits just outside its
  /// thumbnail.
  private static let padding: CGFloat = 2
  private static let cornerRadius: CGFloat = 2
  private static let focusBorder: CGFloat = 1.5

  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let perform: @MainActor (Request) -> Void
  private let menuBuilder: MenuBuilder
  /// What the item shows now (`nil` while hidden), so it is only redrawn when that changes.
  private var map: WorkspaceMap?
  /// Until the first `show`, the item shows nothing yet but is visible.
  private var hasShown = false
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
    // As high as the status item's button allows: the thumbnails fill the menu bar's height.
    let map = WorkspaceMap(snapshot, height: NSStatusBar.system.thickness - 2 * Self.padding)
    guard !hasShown || map != self.map else { return }
    hasShown = true
    self.map = map
    item.isVisible = map != nil
    if let map { item.button?.image = Self.image(for: map) }
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
    let left = (sender.bounds.width - image.size.width) / 2 + Self.padding
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

  /// The map as an image. Not a template image, so the accent colour survives; the colours are
  /// dynamic and resolve against the menu bar's appearance each time the image is drawn.
  private static func image(for map: WorkspaceMap) -> NSImage {
    let size = CGSize(width: map.size.width + 2 * padding, height: map.size.height + 2 * padding)
    return NSImage(size: size, flipped: true) { _ in
      for thumbnail in map.thumbnails {
        draw(thumbnail, offsetBy: padding)
      }
      return true
    }
  }

  private static func draw(_ thumbnail: WorkspaceMap.Thumbnail, offsetBy offset: CGFloat) {
    let slot = thumbnail.frame.offsetBy(dx: offset, dy: offset)
    NSColor.tertiaryLabelColor.setFill()
    NSBezierPath(roundedRect: slot, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    if thumbnail.isCurrent {
      let outline = NSBezierPath(
        roundedRect: slot.insetBy(dx: -1.5, dy: -1.5), xRadius: cornerRadius + 1.5,
        yRadius: cornerRadius + 1.5)
      outline.lineWidth = 1
      NSColor.tertiaryLabelColor.setStroke()
      outline.stroke()
    }
    NSColor.labelColor.setFill()
    for window in thumbnail.windows {
      window.offsetBy(dx: offset, dy: offset).fill()
    }
    // On top, inside the window's rectangle, so it stays visible against the white ones.
    if let index = thumbnail.focusedIndex {
      let inset = focusBorder / 2
      let border = NSBezierPath(
        rect: thumbnail.windows[index].offsetBy(dx: offset, dy: offset).insetBy(
          dx: inset, dy: inset))
      border.lineWidth = focusBorder
      NSColor.controlAccentColor.setStroke()
      border.stroke()
    }
  }
}

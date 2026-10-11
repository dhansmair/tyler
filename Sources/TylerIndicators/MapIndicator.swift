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

  /// The map as an image. Not a template image, so the accent colour survives; the colours are
  /// dynamic and resolve against the menu bar's appearance each time the image is drawn.
  private static func image(for map: WorkspaceMap) -> NSImage {
    NSImage(size: map.size, flipped: true) { _ in
      for thumbnail in map.thumbnails {
        draw(thumbnail)
      }
      return true
    }
  }

  /// The current workspace stands out by brightness, with no outline, so the thumbnails can
  /// take the button's full height: its windows are bright and the others' dimmed, and its slot
  /// is a little brighter, which marks it when it is empty.
  private static func draw(_ thumbnail: WorkspaceMap.Thumbnail) {
    let slotColor: NSColor = thumbnail.isCurrent ? .tertiaryLabelColor : .quaternaryLabelColor
    let windowColor: NSColor = thumbnail.isCurrent ? .labelColor : .secondaryLabelColor
    slotColor.setFill()
    NSBezierPath(roundedRect: thumbnail.frame, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    for (index, window) in thumbnail.windows.enumerated() {
      (index == thumbnail.focusedIndex ? focusColor : windowColor).setFill()
      window.fill()
    }
  }
}

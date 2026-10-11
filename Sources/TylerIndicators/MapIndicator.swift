import AppKit
import OSLog
import TylerCore

/// The map menu bar item: a thumbnail of every workspace with its windows, as `WorkspaceMap`
/// lays them out: the current workspace's windows bright and the others' dimmed, the focused
/// window filled in a light accent colour. A left click on a thumbnail switches to that workspace;
/// a right click or ctrl-click opens the same menu as the text item. Hidden while tiling isn't
/// running, and when `[indicator] map = false`.
@MainActor
public final class MapIndicator: NSObject, Indicator {
  private static let cornerRadius: CGFloat = 2
  private static let log = Logger(subsystem: "tyler", category: "indicator")

  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let perform: @MainActor (Request) -> Void
  private let menuBuilder: MenuBuilder
  /// What the item shows now (`nil` while hidden), so it is only redrawn when that changes.
  private var map: WorkspaceMap?
  /// Until the first `show`, the item shows nothing yet but is visible.
  private var hasShown = false
  /// App icons by process, kept while the process has a window on the map.
  private var icons: [Int32: NSImage] = [:]
  /// SF Symbols by name, kept while a window on the map shows one; `nil` for a name macOS
  /// doesn't know, which falls back to the app's icon.
  private var symbols: [String: NSImage?] = [:]
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
      item.button?.image = Self.image(
        for: map, icons: Icons(apps: icons(for: map), symbols: symbols(for: map)))
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

  /// The icons of the apps with a window on `map`, looked up once per process. Processes no
  /// longer on the map are forgotten.
  private func icons(for map: WorkspaceMap) -> [Int32: NSImage] {
    let processIDs = Set(map.thumbnails.flatMap(\.windows).compactMap(\.processID))
    icons = icons.filter { processIDs.contains($0.key) }
    for processID in processIDs where icons[processID] == nil {
      icons[processID] = NSRunningApplication(processIdentifier: processID)?.icon
    }
    return icons
  }

  /// The SF Symbols the windows on `map` show, looked up once per name. A name macOS doesn't
  /// know is logged once and falls back to the app's icon.
  private func symbols(for map: WorkspaceMap) -> [String: NSImage] {
    let names = Set(map.thumbnails.flatMap(\.windows).compactMap(\.symbol))
    symbols = symbols.filter { names.contains($0.key) }
    for name in names where symbols[name] == nil {
      let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
      if image == nil { Self.log.warning("no SF Symbol named '\(name, privacy: .public)'") }
      symbols[name] = .some(image)
    }
    return symbols.compactMapValues { $0 }
  }

  /// The map as an image. Not a template image, so the accent colour and the app icons survive;
  /// the colours are dynamic and resolve against the menu bar's appearance each time the image
  /// is drawn.
  private static func image(for map: WorkspaceMap, icons: Icons) -> NSImage {
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
  /// dimmed like the window on other workspaces, or the SF Symbol set for the app, cut out of
  /// the window so it reads in light and dark menu bars alike.
  private static func draw(_ thumbnail: WorkspaceMap.Thumbnail, icons: Icons) {
    let slotColor: NSColor = thumbnail.isCurrent ? .tertiaryLabelColor : .quaternaryLabelColor
    let windowColor: NSColor = thumbnail.isCurrent ? .labelColor : .secondaryLabelColor
    slotColor.setFill()
    NSBezierPath(roundedRect: thumbnail.frame, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    for index in thumbnail.drawingOrder {
      let window = thumbnail.windows[index]
      (index == thumbnail.focusedIndex ? focusColor : windowColor).setFill()
      window.frame.fill()
      guard let iconFrame = window.iconFrame else { continue }
      if let symbol = window.symbol.flatMap({ icons.symbols[$0] }) {
        symbol.draw(
          in: aspectFit(symbol.size, in: iconFrame), from: .zero, operation: .destinationOut,
          fraction: 1, respectFlipped: true, hints: nil)
      } else if let icon = window.processID.flatMap({ icons.apps[$0] }) {
        icon.draw(
          in: iconFrame, from: .zero, operation: .sourceOver,
          fraction: thumbnail.isCurrent ? 1 : 0.5, respectFlipped: true, hints: nil)
      }
    }
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

/// What the map draws on its windows: app icons by process and SF Symbols by name.
private struct Icons {
  var apps: [Int32: NSImage]
  var symbols: [String: NSImage]
}

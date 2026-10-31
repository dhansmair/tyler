import AppKit
import CoreGraphics
import TylerCore
import TylerServer

/// The real `WindowStacking`: reads the window server's list of on-screen windows, front to back.
/// The list took 0.6 ms with 49 windows (macOS 26.7; see `devdocs/macos-behaviour.md`).
/// It needs no permission for window numbers, layers and bounds.
@MainActor
package final class MacWindowStacking: WindowStacking {
  /// The layer of menus, context menus and pop-ups (`kCGPopUpMenuWindowLevel`).
  private static let menuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))

  package init() {}

  /// tylerd's own windows (the gap cursor's) are left out: they are never in front of a gap.
  package func topmostWindow(at point: CGPoint) -> StackedWindow? {
    // Bounds are in global display coordinates with a top-left origin, like Accessibility's.
    Self.onScreen().first { !$0.isOwn && $0.frame.contains(point) }?.window
  }

  package var isMenuOpen: Bool {
    Self.onScreen().contains { $0.window.layer == Self.menuLayer }
  }

  package var appWindowsOnScreen: Set<WindowID> {
    let regularApps = Set(
      NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        .map(\.processIdentifier))
    return Set(
      Self.onScreen().filter { listed in
        !listed.isOwn && listed.window.layer == PointerFocus.normalLayer
          && regularApps.contains(listed.ownerID)
      }.map(\.window.id))
  }

  package func containsWindow(_ windowID: WindowID) -> Bool {
    let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID.rawValue)
    // No list says nothing about the window: only an empty one says it is gone.
    return (list as? [[String: Any]])?.isEmpty != true
  }

  private struct Listed {
    let window: StackedWindow
    let frame: CGRect
    let ownerID: pid_t
    let isOwn: Bool
  }

  /// The on-screen windows, front to back, without the overlays clicks go through (the Dock's,
  /// Notification Centre's, the cursor while the screen is shared; see `PointerFocus.isOverlay`).
  private static func onScreen() -> [Listed] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    let displays = displayFrames()
    let ownID = Int(getpid())
    return list.compactMap { entry in
      guard let number = entry[kCGWindowNumber as String] as? UInt32,
        let layer = entry[kCGWindowLayer as String] as? Int,
        let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
        let originX = bounds["X"], let originY = bounds["Y"], let width = bounds["Width"],
        let height = bounds["Height"]
      else { return nil }
      let frame = CGRect(x: originX, y: originY, width: width, height: height)
      if PointerFocus.isOverlay(layer: layer, frame: frame, displayFrames: displays) { return nil }
      let owner = entry[kCGWindowOwnerName as String] as? String
      let window = StackedWindow(id: WindowID(number), layer: layer, owner: owner)
      let ownerID = entry[kCGWindowOwnerPID as String] as? Int ?? 0
      return Listed(window: window, frame: frame, ownerID: pid_t(ownerID), isOwn: ownerID == ownID)
    }
  }

  /// Every active display's frame, in the window list's coordinates (top-left origin).
  private static func displayFrames() -> [CGRect] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).map(CGDisplayBounds)
  }
}

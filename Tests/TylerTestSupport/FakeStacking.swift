import CoreGraphics
import TylerCore

@testable import TylerServer

/// The window server's stacking over a `FakeWindowSystem`: the frontmost window containing a point,
/// with the window system's windows at the normal layer.
@MainActor
package final class FakeStacking: WindowStacking {
  /// Set by `ManagerHarness`, which creates the window system.
  package var windowSystem: FakeWindowSystem?
  /// Windows in front of all of the window system's, such as a menu or the Dock, with their frames.
  package var overlays: [(window: StackedWindow, frame: CGRect)] = []
  /// The window system's windows from front to back; the others follow in the window system's order.
  package var front: [UInt32] = []
  package var isMenuOpen = false
  /// The windows the window server shows; the window system's that aren't minimized when `nil`.
  package var listedWindows: Set<WindowID>?
  /// Every point asked about.
  package private(set) var queries: [CGPoint] = []

  package init() {}

  package var appWindowsOnScreen: Set<WindowID> {
    listedWindows ?? Set((windowSystem?.windows ?? []).filter { !$0.isMinimized }.map(\.id))
  }

  package func topmostWindow(at point: CGPoint) -> StackedWindow? {
    queries.append(point)
    if let overlay = overlays.first(where: { $0.frame.contains(point) }) { return overlay.window }
    let windows = windowSystem?.windows ?? []
    let ordered =
      front.compactMap { id in windows.first { $0.id.rawValue == id } }
      + windows.filter { !front.contains($0.id.rawValue) }
    return ordered.first { $0.frame.contains(point) }.map {
      StackedWindow(id: $0.id, layer: PointerFocus.normalLayer)
    }
  }
}

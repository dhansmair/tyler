import CoreGraphics
import TylerCore

@testable import TylerServer

/// The window server's stacking over a `FakeBackend`: the frontmost window containing a point,
/// with the backend's windows at the normal layer.
@MainActor
package final class FakeStacking: WindowStacking {
  /// Set by `ManagerHarness`, which creates the backend.
  package var backend: FakeBackend?
  /// Windows in front of all of the backend's, such as a menu or the Dock, with their frames.
  package var overlays: [(window: StackedWindow, frame: CGRect)] = []
  /// The backend's windows from front to back; the others follow in the backend's order.
  package var front: [UInt32] = []
  package var isMenuOpen = false
  /// Every point asked about.
  package private(set) var queries: [CGPoint] = []

  package init() {}

  package func topmostWindow(at point: CGPoint) -> StackedWindow? {
    queries.append(point)
    if let overlay = overlays.first(where: { $0.frame.contains(point) }) { return overlay.window }
    let windows = backend?.windows ?? []
    let ordered =
      front.compactMap { id in windows.first { $0.id.rawValue == id } }
      + windows.filter { !front.contains($0.id.rawValue) }
    return ordered.first { $0.frame.contains(point) }.map {
      StackedWindow(id: $0.id, layer: PointerFocus.normalLayer)
    }
  }
}

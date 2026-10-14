import CoreGraphics
import TylerCore

/// How the window server stacks the windows on screen, for finding the window under a point. The
/// real implementation reads the window list (`TylerPlatform.CGWindowStacking`); tests use a fake.
@MainActor
package protocol WindowStacking: AnyObject {
  /// The frontmost on-screen window containing `point` (in Accessibility coordinates), of any
  /// app and at any layer, or `nil` over nothing at all.
  func topmostWindow(at point: CGPoint) -> StackedWindow?
  /// Whether a menu is open: an app's menu, a context menu or a pop-up.
  var isMenuOpen: Bool { get }
}

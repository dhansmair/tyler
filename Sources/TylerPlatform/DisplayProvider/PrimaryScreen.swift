import AppKit
import TylerCore

/// The display with the menu bar, whose height is the origin for converting between AppKit's and
/// Accessibility's coordinates.
@MainActor
enum PrimaryScreen {
  /// `nil` while AppKit lists no screen, as it can during a display change.
  static func appKitRect(fromAX rect: CGRect) -> CGRect? {
    NSScreen.screens.first.map {
      DisplayGeometry.appKitRect(fromAX: rect, primaryScreenHeight: $0.frame.height)
    }
  }
}

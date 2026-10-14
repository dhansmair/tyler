import TylerCore

/// The connected displays, in Accessibility coordinates.
@MainActor
package protocol DisplayProvider: AnyObject {
  /// The primary display (the one with the menu bar) comes first.
  var displays: [DisplayInfo] { get }
  /// Yields each time macOS reports that the displays changed: one was connected or
  /// disconnected, the lid closed, or the arrangement or a resolution changed. Each change
  /// arrives as a burst of several.
  var changes: AsyncStream<Void> { get }
}

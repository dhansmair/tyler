import CoreGraphics
import TylerCore

/// The mouse and trackpad. The real implementation watches system-wide events
/// (`TylerPlatform.MacPointerInput`); tests use a fake.
@MainActor
package protocol PointerInput: AnyObject {
  /// Events from the moment `start()` is called. Subscribe before calling `start()`.
  var events: AsyncStream<PointerEvent> { get }
  /// Whether the primary button is held down right now.
  var isPrimaryButtonDown: Bool { get }
  /// Where the pointer is now, in Accessibility coordinates.
  var location: CGPoint { get }
  func start()
  func stop()
  func watch(_ watch: PointerWatch)
  /// Told when the pointer comes over a gap a press would grab, or leaves it: presses with no
  /// keys in a gap are taken over only in between.
  func gapHovered(_ isOverGap: Bool)
  /// The listeners in place for what `watch` asked for, for `tyler status`.
  var listeners: [InputListener] { get }
  /// Asked at a press that could start a gesture of that kind whether the pointer is over what
  /// it takes: a window that may be moved, or a gap; if not, the press goes to the app.
  var canCapture: (@MainActor (CGPoint, ModifierGesture.Kind) -> Bool)? { get set }
}

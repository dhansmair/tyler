import CoreGraphics

/// Something the mouse or trackpad did that isn't about one window. Window moves and resizes
/// arrive through `WindowBackend`; this carries what tylerd can't learn from the windows.
public enum PointerEvent: Equatable, Sendable {
  /// The primary (left) button went up, anywhere on screen. `location` is in Accessibility
  /// coordinates.
  case primaryButtonReleased(location: CGPoint)
  /// The pointer moved with the primary button down, anywhere on screen. `location` is in
  /// Accessibility coordinates.
  case primaryButtonDragged(location: CGPoint)
}

/// The mouse and trackpad. The real implementation watches system-wide events
/// (`TylerPlatform.PointerMonitor`); tests use a fake.
@MainActor
public protocol PointerInput: AnyObject {
  /// Events from the moment `start()` is called. Subscribe before calling `start()`.
  var events: AsyncStream<PointerEvent> { get }
  /// Whether the primary button is held down right now.
  var isPrimaryButtonDown: Bool { get }
  func start()
  func stop()
}

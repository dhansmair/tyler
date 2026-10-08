import MWMCore

/// A change in the set of windows, reported by a `WindowBackend`.
public enum WindowEvent: Equatable, Sendable {
  case created(WindowInfo)
  case updated(WindowInfo)
  case destroyed(WindowID)
  /// The focused window changed; `nil` when no window has focus.
  case focused(WindowID?)
}

/// Source of window information. The real implementation talks to the Accessibility API
/// (`MWMPlatform.AXBackend`); tests use a fake.
@MainActor
public protocol WindowBackend: AnyObject {
  /// Events from the moment `start()` is called. Subscribe before calling `start()`.
  var events: AsyncStream<WindowEvent> { get }
  /// Begins observing. Only call once the process has Accessibility permission.
  func start()
  /// Every window currently known, with `isFocused` set on at most one.
  func snapshot() -> [WindowInfo]
  func stop()
}

/// The connected displays, in Accessibility coordinates.
@MainActor
public protocol DisplayProvider: AnyObject {
  var displays: [DisplayInfo] { get }
}

/// Whether this process may use the Accessibility API.
@MainActor
public protocol AccessibilityGate: AnyObject {
  var isTrusted: Bool { get }
  /// Asks macOS to show its permission prompt. Safe to call repeatedly.
  func prompt()
}

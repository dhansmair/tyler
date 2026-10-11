import CoreGraphics
import TylerCore

/// A change in the set of windows, reported by a `WindowBackend`.
public enum WindowEvent: Equatable, Sendable {
  case created(WindowInfo)
  case updated(WindowInfo)
  case destroyed(WindowID)
  /// The focused window changed; `nil` when no window has focus.
  case focused(WindowID?)
}

/// Why a backend could not act on a window.
public enum BackendError: Error, Equatable, Sendable, CustomStringConvertible {
  /// The window closed (or its app quit) before the action reached it.
  case windowGone(WindowID)
  /// The app or the system refused; the text says why.
  case refused(String)

  public var description: String {
    switch self {
    case .windowGone: "the window no longer exists"
    case .refused(let reason): reason
    }
  }
}

/// Source of window information and the means to act on windows. The real implementation talks
/// to the Accessibility API (`TylerPlatform.AXBackend`); tests use a fake.
@MainActor
public protocol WindowBackend: AnyObject {
  /// Events from the moment `start()` is called. Subscribe before calling `start()`.
  var events: AsyncStream<WindowEvent> { get }
  /// Begins observing. Only call once the process has Accessibility permission.
  func start()
  /// Every window currently known, with `isFocused` set on at most one.
  func snapshot() -> [WindowInfo]
  func stop()

  /// Moves and resizes a window. The frame is in Accessibility coordinates. Apps may clamp the
  /// size, so the result is reported back through `events`, not assumed.
  func setFrame(_ frame: CGRect, of windowID: WindowID) throws(BackendError)
  /// Moves a window without resizing it, in a single call to the app. Used for the steps of an
  /// animation, so it doesn't report the new frame back; the app's own notifications do that.
  func setPosition(_ origin: CGPoint, of windowID: WindowID) throws(BackendError)
  /// Raises a window and gives it keyboard focus, bringing its app forward.
  func focus(_ windowID: WindowID) throws(BackendError)
  /// Takes keyboard focus away from every window, so that what is typed next reaches none of
  /// them.
  func unfocus() throws(BackendError)
}

/// The connected displays, in Accessibility coordinates.
@MainActor
public protocol DisplayProvider: AnyObject {
  /// The primary display (the one with the menu bar) comes first.
  var displays: [DisplayInfo] { get }
  /// Yields each time macOS reports that the displays changed: one was connected or
  /// disconnected, the lid closed, or the arrangement or a resolution changed. Each change
  /// arrives as a burst of several.
  var changes: AsyncStream<Void> { get }
}

/// Whether this process may use the Accessibility API.
@MainActor
public protocol AccessibilityGate: AnyObject {
  var isTrusted: Bool { get }
  /// Asks macOS to show its permission prompt. Safe to call repeatedly.
  func prompt()
}

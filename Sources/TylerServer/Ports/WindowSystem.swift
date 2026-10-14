import CoreGraphics
import TylerCore

/// Source of window information and the means to act on windows. The real implementation talks
/// to the Accessibility API (`TylerPlatform.MacWindowSystem`); tests use a fake.
@MainActor
package protocol WindowSystem: AnyObject {
  /// Events from the moment `start()` is called. Subscribe before calling `start()`.
  var events: AsyncStream<WindowEvent> { get }
  /// Begins observing. Only call once the process has Accessibility permission.
  func start()
  /// Every window currently known, with `isFocused` set on at most one.
  func snapshot() -> [WindowInfo]
  /// Every tracked window read again, the observed apps' windows it doesn't track, and the apps it
  /// couldn't observe: for `tyler debug windows`, which compares them with tylerd's picture.
  func freshWindows() -> FreshWindows
  func stop()

  /// Moves and resizes a window. The frame is in Accessibility coordinates. Apps may clamp the
  /// size, so the result is reported back through `events`, not assumed.
  func setFrame(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError)
  /// Moves a window without resizing it, in a single call to the app. Used for the steps of an
  /// animation, so it doesn't report the new frame back; the app's own notifications do that. It
  /// may return before the app has moved the window, and a newer move may replace one still
  /// waiting; a later `setFrame` of the window always lands after it.
  func setPosition(_ origin: CGPoint, of windowID: WindowID) throws(WindowSystemError)
  /// Moves and resizes a window as `setPosition` moves it: for the steps of an animation that
  /// changes a window's size, settled by a `setFrame` at the end.
  func setFrameStep(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError)
  /// What `setPosition` and `setFrameStep` wrote without waiting since the last call.
  func takeQueuedWrites() -> MotionCost.Queued
  /// Moves and resizes a window in at most two calls to the app, without reading it back: for the
  /// steps of a resize, which a `setFrame` settles at the end.
  func setFrameInPassing(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError)
  /// Raises a window and gives it keyboard focus, bringing its app forward.
  func focus(_ windowID: WindowID) throws(WindowSystemError)
  /// Presses the window's close button. The window is gone once `events` says so: an app may
  /// first ask whether to save it.
  func close(_ windowID: WindowID) throws(WindowSystemError)
  /// Takes keyboard focus away from every window, so that what is typed next reaches none of
  /// them.
  func unfocus() throws(WindowSystemError)
}

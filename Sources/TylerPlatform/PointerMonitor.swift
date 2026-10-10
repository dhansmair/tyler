import AppKit
import TylerCore
import TylerServer

/// The real `PointerInput`: reads the mouse button state from AppKit and watches the primary
/// button dragging and going up anywhere on screen through a global event monitor. Global monitors
/// only see events sent to other apps, which is every click that matters: tylerd has no windows
/// of its own, only the menu bar item. Trackpad swipes come from a `SwipeTap`.
@MainActor
public final class PointerMonitor: PointerInput {
  public let events: AsyncStream<PointerEvent>

  private let continuation: AsyncStream<PointerEvent>.Continuation
  private var monitor: Any?
  private var swipeTap: SwipeTap?

  public init() {
    (events, continuation) = AsyncStream.makeStream(of: PointerEvent.self)
  }

  public var isPrimaryButtonDown: Bool {
    NSEvent.pressedMouseButtons & 1 != 0
  }

  public func start() {
    guard monitor == nil else { return }
    // AppKit calls global monitors on the main thread, which is what makes `assumeIsolated` safe.
    let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
    monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
      let isRelease = event.type == .leftMouseUp
      MainActor.assumeIsolated { self?.report(isRelease: isRelease) }
    }
  }

  public func stop() {
    watchSwipes(fingers: nil)
    guard let monitor else { return }
    NSEvent.removeMonitor(monitor)
    self.monitor = nil
  }

  public func watchSwipes(fingers: Int?) {
    guard fingers != swipeTap?.fingers else { return }
    swipeTap?.invalidate()
    swipeTap = nil
    guard let fingers else { return }
    swipeTap = SwipeTap(fingers: fingers) { [weak self] update in
      self?.continuation.yield(.pan(update))
    }
  }

  /// Reports a drag step or the release with where the pointer is, in Accessibility coordinates
  /// (top-left origin on the primary display).
  private func report(isRelease: Bool) {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let location = DisplayGeometry.axRect(
      fromAppKit: CGRect(origin: NSEvent.mouseLocation, size: .zero),
      primaryScreenHeight: primaryHeight
    ).origin
    continuation.yield(
      isRelease
        ? .primaryButtonReleased(location: location) : .primaryButtonDragged(location: location))
  }
}

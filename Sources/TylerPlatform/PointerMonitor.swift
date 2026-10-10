import AppKit
import TylerCore
import TylerServer

/// The real `PointerInput`: reads the mouse button state from AppKit and watches for the
/// primary button going up anywhere on screen through a global event monitor. Global monitors
/// only see events sent to other apps, which is every click that matters: tylerd has no windows
/// of its own, only the menu bar item.
@MainActor
public final class PointerMonitor: PointerInput {
  public let events: AsyncStream<PointerEvent>

  private let continuation: AsyncStream<PointerEvent>.Continuation
  private var monitor: Any?

  public init() {
    (events, continuation) = AsyncStream.makeStream(of: PointerEvent.self)
  }

  public var isPrimaryButtonDown: Bool {
    NSEvent.pressedMouseButtons & 1 != 0
  }

  public func start() {
    guard monitor == nil else { return }
    // AppKit calls global monitors on the main thread, which is what makes `assumeIsolated` safe.
    monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
      MainActor.assumeIsolated { self?.primaryButtonReleased() }
    }
  }

  public func stop() {
    guard let monitor else { return }
    NSEvent.removeMonitor(monitor)
    self.monitor = nil
  }

  /// Reports the release with where the pointer is, in Accessibility coordinates (top-left
  /// origin on the primary display).
  private func primaryButtonReleased() {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let location = DisplayGeometry.axRect(
      fromAppKit: CGRect(origin: NSEvent.mouseLocation, size: .zero),
      primaryScreenHeight: primaryHeight
    ).origin
    continuation.yield(.primaryButtonReleased(location: location))
  }
}

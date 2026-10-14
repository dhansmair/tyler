import AppKit
import TylerCore
import TylerRuntime
import TylerServer

/// The real `GapCursor`: an empty borderless window over the gap that shows the resize cursor. At
/// the normal level, so another app's window brought over the gap covers it. A press there still
/// reaches the event tap first, but a click lands on this window rather than the desktop.
///
/// Measured: `NSCursor.set()` from tylerd in the background is undone at once, even after the
/// private `SetsCursorInBackground` call; with that call and the window under the pointer taking
/// mouse events (a tracking area setting the cursor), the resize cursor shows. Whether the
/// private call is still needed with the window was not settled.
@MainActor
package final class GapCursorWindow: GapCursor {
  private let window: NSWindow
  private let content = CursorView()

  package init() {
    window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    // Set on purpose: by default, the clear parts of a window let mouse events through.
    window.ignoresMouseEvents = false
    window.level = .normal
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .transient]
    window.contentView = content
    Self.setsCursorInBackground()
  }

  package func show(over area: CGRect) {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    // The flip between Accessibility and AppKit coordinates is its own inverse.
    let frame = DisplayGeometry.axRect(fromAppKit: area, primaryScreenHeight: primaryHeight)
    window.setFrame(frame, display: false)
    window.orderFrontRegardless()
    content.cursor = area.height >= area.width ? .resizeLeftRight : .resizeUpDown
    content.cursor.set()
  }

  package func hide() {
    window.orderOut(nil)
    NSCursor.arrow.set()
  }

  private static func setsCursorInBackground() {
    let connection = windowServerConnection()
    let status = setConnectionProperty(
      connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    if status != .success {
      log.warning("cursor setting refused - in the background - error \(status.rawValue)")
    }
  }

  private static let log = TylerLog(category: "pointer")

  /// Sets its cursor whenever the pointer enters or moves over it, even with tylerd in the
  /// background.
  private final class CursorView: NSView {
    var cursor = NSCursor.resizeLeftRight

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      for area in trackingAreas { removeTrackingArea(area) }
      addTrackingArea(
        NSTrackingArea(
          rect: .zero,
          options: [
            .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect,
          ],
          owner: self))
    }

    override func mouseEntered(with event: NSEvent) { cursor.set() }
    override func mouseMoved(with event: NSEvent) { cursor.set() }
    override func cursorUpdate(with event: NSEvent) { cursor.set() }
  }
}

// The window server's private calls, in CoreGraphics (SkyLight) since macOS 10.x.
@_silgen_name("CGSMainConnectionID")
private func windowServerConnection() -> Int32

@_silgen_name("CGSSetConnectionProperty")
private func setConnectionProperty(
  _ connection: Int32, _ target: Int32, _ key: CFString, _ value: CFTypeRef
) -> CGError

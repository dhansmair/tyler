import CoreGraphics
import TylerCore

/// A tiled window the user is dragging with the primary button down.
struct MouseDrag: Equatable {
  let windowID: WindowID
  /// The newest frame of a resize that the layout hasn't followed yet.
  var pendingFrame: CGRect?
}

extension WindowManager {
  // MARK: - Mouse

  /// Starts listening to the pointer, if there is one. Subscribes before starting it, like the
  /// window events, so no event is lost.
  func startPointer() {
    guard let pointer else { return }
    let events = pointer.events
    pointerPump = Task { [weak self] in
      for await event in events {
        self?.apply(event)
      }
    }
    pointer.start()
  }

  /// Follows a window the user is resizing with the mouse: the layout moves the dividers whose
  /// edges are being dragged, and the other windows follow. Only one window counts per drag, the
  /// first that leaves its slot while the button is down, so the updates that tylerd's own moves
  /// of the other windows cause are ignored. The dragged window itself is never moved mid-drag
  /// (that would fight the user); it snaps into its slot on release. A window that was only
  /// moved, not resized, changes nothing until then.
  ///
  /// Following a drag moves every other window, one round trip to its app each, and apps like
  /// Firefox take long enough that the resize events of a drag pile up faster than they can be
  /// followed. So the first resize is followed at once, later ones at most once per
  /// `mouse.follow-interval` from the config: frames arriving in between replace each other, and
  /// only the newest is followed.
  func followDrag(of window: WindowInfo) {
    guard let pointer, pointer.isPrimaryButtonDown, state == .running, tilingEnabled,
      animation == nil, workspaces.current.contains(window.id)
    else { return }
    if let drag, drag.windowID != window.id { return }
    guard let area = displays.displays.first?.visibleFrame,
      let slot = workspaces.current.placements(in: area).first(where: { $0.id == window.id })
    else { return }
    if drag == nil {
      guard !Self.isClose(window.frame, slot.frame) else { return }
      drag = MouseDrag(windowID: window.id)
    }
    guard Self.isResized(window.frame, from: slot.frame) else { return }
    drag?.pendingFrame = window.frame
    if dragThrottle == nil { followPendingFrame() }
  }

  /// Ends a drag: the last size the dragged window had counts, then every window, the dragged
  /// one included, goes to its slot. A window that was moved goes back where it came from.
  func apply(_ event: PointerEvent) {
    switch event {
    case .primaryButtonReleased:
      guard let drag else { return }
      endDrag()
      guard state == .running, tilingEnabled, animation == nil,
        workspaces.current.contains(drag.windowID),
        let area = displays.displays.first?.visibleFrame,
        let frame = registry.window(withID: drag.windowID)?.frame,
        let slot = workspaces.current.placements(in: area).first(where: { $0.id == drag.windowID })
      else { return }
      if Self.isResized(frame, from: slot.frame) {
        workspaces.current.resize(drag.windowID, to: frame, in: area)
      }
      applyLayout()
    }
  }

  /// Forgets the drag, and any step of it still waiting.
  func endDrag() {
    drag = nil
    dragThrottle?.cancel()
    dragThrottle = nil
  }

  /// Follows the newest frame of the drag, if there is one, then holds further steps back for
  /// the follow interval. When the interval is up, a frame that arrived meanwhile is followed the
  /// same way; with none, the next resize is followed at once again.
  private func followPendingFrame() {
    guard let windowID = drag?.windowID, let frame = drag?.pendingFrame else {
      dragThrottle = nil
      return
    }
    drag?.pendingFrame = nil
    follow(windowID, to: frame)
    let interval = Duration.milliseconds(config.mouse.followInterval)
    guard interval > .zero else { return }
    let clock = clock  // Swift opens the existential from a local, not from the stored property.
    dragThrottle = Task { [weak self] in
      do {
        try await clock.sleep(for: interval)
      } catch {
        return  // Cancelled: the drag ended.
      }
      self?.followPendingFrame()
    }
  }

  /// Lets the layout follow `windowID` having been resized to `frame`, and moves every other
  /// window that is now out of its slot.
  private func follow(_ windowID: WindowID, to frame: CGRect) {
    guard let area = displays.displays.first?.visibleFrame,
      workspaces.current.resize(windowID, to: frame, in: area)
    else { return }
    place(
      workspaces.current.placements(in: area).filter { placement in
        placement.id != windowID && !isInPlace(placement)
      })
  }

  /// Whether `frame` has another size than `slot`; one of the same size was moved, not resized.
  private static func isResized(_ frame: CGRect, from slot: CGRect) -> Bool {
    abs(frame.width - slot.width) > 1 || abs(frame.height - slot.height) > 1
  }
}

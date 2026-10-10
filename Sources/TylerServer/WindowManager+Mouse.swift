import CoreGraphics
import TylerCore

/// A tiled window the user is dragging with the primary button down.
struct MouseDrag: Equatable {
  let windowID: WindowID
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
  /// edges are being dragged, and the other windows follow at once. Only one window counts per
  /// drag, the first that leaves its slot while the button is down, so the updates that tylerd's
  /// own moves of the other windows cause are ignored. The dragged window itself is never moved
  /// mid-drag (that would fight the user); it snaps into its slot on release. A window that was
  /// only moved, not resized, changes nothing until then.
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
    guard follow(window.id, to: window.frame, slot: slot.frame, in: area) else { return }
    place(
      workspaces.current.placements(in: area).filter { placement in
        placement.id != window.id && !isInPlace(placement)
      })
  }

  /// Ends a drag: the last size the dragged window had counts, then every window, the dragged
  /// one included, goes to its slot. A window that was moved goes back where it came from.
  func apply(_ event: PointerEvent) {
    switch event {
    case .primaryButtonReleased:
      guard let drag else { return }
      self.drag = nil
      guard state == .running, tilingEnabled, animation == nil,
        workspaces.current.contains(drag.windowID),
        let area = displays.displays.first?.visibleFrame,
        let frame = registry.window(withID: drag.windowID)?.frame,
        let slot = workspaces.current.placements(in: area).first(where: { $0.id == drag.windowID })
      else { return }
      follow(drag.windowID, to: frame, slot: slot.frame, in: area)
      applyLayout()
    }
  }

  /// Lets the layout follow `windowID` having been resized to `frame` from `slot`. A frame of
  /// the slot's size was moved, not resized, and changes nothing. Returns whether the layout
  /// changed.
  @discardableResult
  private func follow(
    _ windowID: WindowID, to frame: CGRect, slot: CGRect, in area: CGRect
  ) -> Bool {
    let isResized = abs(frame.width - slot.width) > 1 || abs(frame.height - slot.height) > 1
    return isResized && workspaces.current.resize(windowID, to: frame, in: area)
  }
}

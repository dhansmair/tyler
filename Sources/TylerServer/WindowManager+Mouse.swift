import CoreGraphics
import TylerCore

/// A tiled window the user is dragging with the primary button down.
struct MouseDrag: Equatable {
  let windowID: WindowID
  /// The newest frame of a resize that the layout hasn't followed yet.
  var pendingFrame: CGRect?
  /// Whether the window changed size, not only place. A resize never swaps.
  var isResize = false
  /// The window shown in the dragged window's slot, the one a release would swap with.
  var previewTarget: WindowID?
  /// Follows resizes at most once per `mouse.follow-interval`.
  var throttle = Throttle()
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
    applyGestures()
  }

  /// Has the pointer watch for the configured swipe, or stop watching when swipes are off.
  func applyGestures() {
    pointer?.watchSwipes(fingers: config.gestures.swipe ? config.gestures.fingers : nil)
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
  ///
  /// A window moved by its title bar can swap with another: see `previewDrop(at:)`.
  func followDrag(of window: WindowInfo) {
    guard let pointer, pointer.isPrimaryButtonDown, isTiling,
      interaction.allowsDrag, workspaces.current.contains(window.id)
    else { return }
    if let drag, drag.windowID != window.id { return }
    guard let slot = slot(of: window.id) else { return }
    if drag == nil {
      guard !Self.isClose(window.frame, slot.frame) else { return }
      drag = MouseDrag(windowID: window.id)
    }
    guard Self.isResized(window.frame, from: slot.frame) else { return }
    drag?.isResize = true
    drag?.pendingFrame = window.frame
    if drag?.throttle.isHolding == false { followPendingFrame() }
  }

  func apply(_ event: PointerEvent) {
    switch event {
    case .primaryButtonDragged(let location): previewDrop(at: location)
    case .primaryButtonReleased(let location): drop(at: location)
    case .pan(let update): apply(update)
    }
  }

  /// Ends a drag: the last size the dragged window had counts, then every window, the dragged
  /// one included, goes to its slot. A window that was moved, not resized, onto another tiled
  /// window's slot swaps with it; moved anywhere else, it goes back where it came from.
  private func drop(at location: CGPoint) {
    guard let drag else { return }
    let canTile = canFollow(drag)
    if canTile { settle(drag, droppedAt: location) }
    endDrag()
    if canTile { applyLayout() }
  }

  /// Updates the workspace for how `drag` ended: a resize moves the dividers, a move onto
  /// another window's slot swaps the two.
  private func settle(_ drag: MouseDrag, droppedAt location: CGPoint) {
    guard let area = primaryDisplay?.visibleFrame, let placements = currentPlacements(),
      let frame = registry.window(withID: drag.windowID)?.frame,
      let slot = placements.first(where: { $0.id == drag.windowID })
    else { return }
    if Self.isResized(frame, from: slot.frame) {
      workspaces.current.resize(drag.windowID, to: frame, in: area)
      return
    }
    guard !drag.isResize,
      let target = Workspace.dropTarget(for: drag.windowID, at: location, among: placements)
    else { return }
    workspaces.current.swap(drag.windowID, with: target)
  }

  /// Shows what a release at `location` would do: while the pointer is over another tiled
  /// window's slot, that window moves into the dragged window's slot, and back to its own when
  /// the pointer leaves it. Windows move only when the target changes, not with every step of
  /// the pointer. Their moves are reported back as updates, which `followDrag` ignores, since
  /// only the dragged window counts. This runs for every step of the pointer, so the workspace is
  /// laid out once per step.
  private func previewDrop(at location: CGPoint) {
    guard let drag, !drag.isResize, canFollow(drag), let placements = currentPlacements()
    else { return }
    let target = Workspace.dropTarget(for: drag.windowID, at: location, among: placements)
    guard target != drag.previewTarget else { return }
    var moves = placements.filter { $0.id == drag.previewTarget }
    if let target, let slot = placements.first(where: { $0.id == drag.windowID }) {
      moves.append(Placement(id: target, frame: slot.frame))
    }
    self.drag?.previewTarget = target
    place(moves)
  }

  /// Forgets the drag, and any step of it still waiting. A window the preview moved into the
  /// dragged window's slot goes back to its own, so a command or a workspace switch in the middle
  /// of a drag never leaves two windows in each other's slots.
  func endDrag() {
    let previewTarget = drag?.previewTarget
    drag?.throttle.release()
    drag = nil
    guard let previewTarget, isTiling, let slot = slot(of: previewTarget), !isInPlace(slot)
    else { return }
    place([slot])
  }

  /// Forgets the preview target without moving it, for a window that is gone.
  func forgetPreviewTarget(_ windowID: WindowID) {
    if drag?.previewTarget == windowID { drag?.previewTarget = nil }
  }

  /// Whether the layout can still react to `drag`: tiling runs, no slide, and the dragged window
  /// is still tiled on the workspace on screen.
  private func canFollow(_ drag: MouseDrag) -> Bool {
    isTiling && interaction.allowsDrag
      && workspaces.current.contains(drag.windowID)
  }

  /// Follows the newest frame of the drag, if there is one, then holds further steps back for
  /// the follow interval. When the interval is up, a frame that arrived meanwhile is followed the
  /// same way; with none, the next resize is followed at once again.
  private func followPendingFrame() {
    guard let windowID = drag?.windowID, let frame = drag?.pendingFrame else {
      drag?.throttle.release()
      return
    }
    drag?.pendingFrame = nil
    follow(windowID, to: frame)
    drag?.throttle.hold(for: .milliseconds(config.mouse.followInterval), on: clock) {
      [weak self] in
      self?.followPendingFrame()
    }
  }

  /// Lets the layout follow `windowID` having been resized to `frame`, and moves every other
  /// window that is now out of its slot.
  private func follow(_ windowID: WindowID, to frame: CGRect) {
    guard let area = primaryDisplay?.visibleFrame,
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

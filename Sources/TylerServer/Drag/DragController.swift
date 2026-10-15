import CoreGraphics
import TylerCore
import TylerRuntime

/// Dragging a tiled window, by its title bar or edges or with the modifier: when a drag starts,
/// what the preview shows, how the layout follows a resize, and what a drop does. `DragSession`
/// decides the preview and the drop; this changes the lists and says which windows move.
struct DragController {
  /// What a window update means for the drag: the drag it starts or goes on with, and the frame
  /// of a resize for the layout to follow.
  struct Step {
    var session: DragSession
    var pendingFrame: CGRect?
  }

  private static let log = TylerLog(category: "manager")

  let context: ControllerContext

  /// Only one window counts per drag, the first that leaves its slot while the button is down,
  /// so the updates that tylerd's own moves of the other windows cause are ignored. The dragged
  /// window itself is never moved mid-drag (that would fight the user); it snaps into its slot
  /// on release. A window that was only moved, not resized, changes nothing until then.
  ///
  /// The drag works on the dragged window's own display, whichever display has focus: the focus
  /// event of a window the user starts dragging can arrive after its first moves. Starting a
  /// drag focuses that display. `nil` when the update means nothing to a drag.
  ///
  /// A drag that changes the window's size from what it was before the drag is a resize. Not
  /// its slot's: an app may keep a window smaller than its slot (System Settings keeps its width).
  func windowUpdated(
    _ window: WindowInfo, from previous: CGRect?, session: DragSession?, model: inout Model
  ) -> Step? {
    let tiling = tiling(model.rows)
    guard context.isPrimaryButtonDown, context.isTiling(model), context.allowsDrag,
      let position = tiling.onScreenPosition(of: window.id)
    else { return nil }
    // tylerd moves a grabbed window itself: the updates are its own.
    if let session, session.windowID != window.id || session.grab != nil { return nil }
    guard let slot = tiling.slot(of: window.id) else { return nil }
    var step: Step
    if let session {
      step = Step(session: session)
    } else {
      guard !window.frame.isClose(to: slot.frame) else { return nil }
      step = Step(session: DragSession(windowID: window.id, startFrame: previous ?? slot.frame))
      model.rows.focus(model.rows.entries[position].key)
      Self.log.info("window dragging started - \(named(window.id)) - on display \(position + 1)")
    }
    // Over another display, a window can change size on its own (another scale, terminals
    // snapping to cells): that is still a move, not a resize.
    guard window.frame.hasOtherSize(than: step.session.startFrame ?? slot.frame),
      !isOverAnotherDisplay(window, than: position, in: model.rows)
    else { return step }
    if !step.session.isResize {
      Self.log.info("window resizing started - \(named(window.id)) - by its edges")
    }
    step.session.isResize = true
    step.pendingFrame = window.frame
    return step
  }

  /// The layout follows `windowID` having been resized to `frame`, and every other window now
  /// out of its slot moves. A grabbed window moves too (`movesItself` is false): no app is
  /// resizing it.
  func follow(
    _ windowID: WindowID, to frame: CGRect, movesItself: Bool, model: inout Model
  ) -> [Effect] {
    let tiling = tiling(model.rows)
    guard let position = tiling.onScreenPosition(of: windowID),
      let display = context.display(for: model.rows.entries[position].key),
      model.rows[position].current.resize(
        windowID, to: frame, in: display.visibleFrame, gaps: context.gaps)
    else { return [] }
    let placements = model.rows[position].current.placements(on: display, gaps: context.gaps)
    let moves = context.moves(toward: placements.filter { $0.id != windowID || !movesItself })
    return [.placeInPassing(moves)]
  }

  /// Windows move only when the target changes, not with every step of the pointer. Their moves
  /// are reported back as updates, which `windowUpdated` ignores, since only the dragged window
  /// counts.
  func previewDrop(at location: CGPoint, session: inout DragSession, model: Model) -> [Effect] {
    guard !session.isResize, canFollow(session, model) else { return [] }
    let tiling = tiling(model.rows)
    if let arrival = session.arrival(at: location, in: tiling) {
      return [.place(context.moves(toward: session.preview(arrival, in: tiling)))]
    }
    let undo = context.moves(toward: session.undoArrival(in: tiling))
    let duration = Duration.milliseconds(context.config.animations.dragPreview)
    return [.place(undo), .preview(session.previewMove(at: location, in: tiling), over: duration)]
  }

  /// The last size the dragged window had counts, then every window, the dragged one included,
  /// goes to its slot. A window that was moved, not resized, onto another tiled window's slot
  /// goes in there, the others making room; over another display, it joins the workspace on screen there, where the
  /// preview showed it, and that display gets the focus; moved anywhere else, it goes back.
  func drop(at location: CGPoint, session: inout DragSession, model: inout Model) -> [Effect] {
    let windowID = session.windowID
    guard canFollow(session, model) else {
      Self.log.info("window dropped - \(named(windowID)) - on its own display; not tiling it")
      return endingEffects(&session, model: model)
    }
    let frame = context.registry.window(withID: windowID)?.frame
    switch session.drop(at: location, frame: frame, in: tiling(model.rows)) {
    case .arrive(let arrival):
      Self.log.info(
        "window dropped - \(named(windowID)) - on display \(arrival.position + 1) at "
          + "\(Int(location.x)),\(Int(location.y))")
      // The windows there are where the drop puts them already: they stay.
      session.forgetArrival()
      let end = endingEffects(&session, model: model)
      let row = model.rows[arrival.position]
      let windows = row.current.windows
      model.rows.dropWindow(
        windowID, toNumber: row.number(at: row.currentIndex),
        before: windows.indices.contains(arrival.index) ? windows[arrival.index] : nil)
      model.rows.focus(model.rows.entries[arrival.position].key)
      return end + [.reconcile()]
    case .resize(let position, let frame):
      logDroppedOnItsOwnDisplay(windowID)
      if let area = context.display(for: model.rows.entries[position].key)?.visibleFrame {
        model.rows[position].current.resize(windowID, to: frame, in: area, gaps: context.gaps)
      }
    case .move(let position, let place):
      logDroppedOnItsOwnDisplay(windowID)
      // The windows are where the preview put them, if it showed this place: they stay.
      session.forgetMovePreview()
      model.rows[position].current.move(windowID, to: place)
    case .back:
      logDroppedOnItsOwnDisplay(windowID)
    }
    return endingEffects(&session, model: model) + [.reconcile()]
  }

  /// The moves that end a drag: windows the preview moved go back to their slots, so a command
  /// or a workspace switch in the middle of a drag never leaves windows in other windows' slots,
  /// or a display laid out for a window that never came. The windows the move preview moved go
  /// back whatever the registry says: an animated preview's steps aren't reported back at once.
  func endingEffects(_ session: inout DragSession, model: Model) -> [Effect] {
    let tiling = tiling(model.rows)
    let undo: [Effect] = [.place(context.moves(toward: session.undoArrival(in: tiling)))]
    let unmoved = session.undoMovePreview(in: tiling)
    guard !unmoved.isEmpty, context.isTiling(model) else { return undo }
    return undo + [.place(unmoved)]
  }

  // MARK: - With the modifier

  func beginGrab(
    _ kind: ModifierGesture.Kind, of windowID: WindowID, at start: CGPoint, model: inout Model
  ) -> (session: DragSession, effects: [Effect])? {
    guard let frame = context.registry.window(withID: windowID)?.frame else { return nil }
    let tiling = tiling(model.rows)
    let isFloated = model.bookkeeping.floated.contains(windowID)
    var session = DragSession(windowID: windowID)
    session.isResize = kind == .resize
    // A tiled window is resized through the layout, which measures from its slot. A window that
    // isn't quite in it (one macOS wouldn't shrink, say) would otherwise seem to have moved both
    // edges, and the layout would ignore every step.
    let slotFrame = kind == .resize && !isFloated ? tiling.slot(of: windowID)?.frame : nil
    var edges = ResizeEdges(grabbedAt: start, in: frame)
    let position = tiling.onScreenPosition(of: windowID)
    if let slotFrame, let position {
      let offView = tiling.offViewWindows
      let others = tiling.restingPlacements(at: position)
        .filter { $0.id != windowID && !offView.contains($0.id) }.map(\.frame)
      edges = edges.towardNeighbours(of: slotFrame, among: others)
    }
    session.grab = ModifierGrab(
      kind: kind, start: start, frame: slotFrame ?? frame, edges: edges, isFloated: isFloated)
    if let position {
      model.rows.focus(model.rows.entries[position].key)
    }
    Self.log.info(
      "window \(kind == .move ? "moving" : "resizing") started - \(named(windowID)) - "
        + "with the modifier")
    return (session, [.focus(windowID)])
  }

  // MARK: - In a gap

  /// The gap between two tiled windows at `location`, on the workspace in view there.
  func gap(at location: CGPoint, model: Model) -> GapGrab? {
    let tiling = tiling(model.rows)
    guard context.isTiling(model), context.allowsDrag,
      let position = tiling.position(under: location)
    else { return nil }
    return GapGrab(at: location, among: tiling.restingPlacements(at: position))
  }

  /// A drag in a gap resizes the window before it through the layout, as a resize with the
  /// modifier does, but leaves the focus where it is: a divider isn't a window.
  func beginGapGrab(_ gap: GapGrab, at start: CGPoint, model: Model) -> DragSession? {
    guard let slot = tiling(model.rows).slot(of: gap.windowID) else { return nil }
    var session = DragSession(windowID: gap.windowID)
    session.isResize = true
    session.grab = ModifierGrab(
      kind: .gap, start: start, frame: slot.frame, edges: gap.edge, isFloated: false)
    Self.log.info("window resizing started - \(named(gap.windowID)) - by the gap beside it")
    return session
  }

  // MARK: - With the modifier, or in a gap

  /// A move takes the window along and shows where a drop would put it; a resize of a floated
  /// window resizes it at once, of a tiled window gives the frame for the layout to follow.
  func moveGrab(
    to location: CGPoint, session: inout DragSession, model: Model
  ) -> (effects: [Effect], pendingFrame: CGRect?) {
    guard let grab = session.grab else { return ([], nil) }
    let delta = CGVector(dx: location.x - grab.start.x, dy: location.y - grab.start.y)
    switch grab.kind {
    case .move:
      let origin = CGPoint(x: grab.frame.minX + delta.dx, y: grab.frame.minY + delta.dy)
      let carry = Effect.carry(Nudge(id: session.windowID, origin: origin))
      return ([carry] + previewDrop(at: location, session: &session, model: model), nil)
    case .resize, .gap:
      let frame = grab.frame.resizing(grab.edges, by: delta)
      guard grab.isFloated else { return ([], frame) }
      return ([.carryFrame(Placement(id: session.windowID, frame: frame))], nil)
    }
  }

  /// After the drop: a moved window's frame may not have been reported back yet, so the layout
  /// can take it for in place. A tiled window moved with the modifier goes into its slot,
  /// whatever the registry says; a floated one stays where it was left.
  func settleGrabbed(_ grab: ModifierGrab, windowID: WindowID, model: Model) -> [Effect] {
    guard grab.kind == .move, !grab.isFloated, let slot = tiling(model.rows).slot(of: windowID)
    else { return [] }
    return [.place([slot])]
  }

  /// Tiling runs, no slide or swipe, and the dragged window is still tiled on the workspace on
  /// screen on its display.
  private func canFollow(_ session: DragSession, _ model: Model) -> Bool {
    context.isTiling(model) && context.allowsDrag
      && tiling(model.rows).onScreenPosition(of: session.windowID) != nil
  }

  private func isOverAnotherDisplay(
    _ window: WindowInfo, than position: Int, in rows: DisplayRows
  ) -> Bool {
    DisplayGeometry.display(containing: window.frame, in: context.displays)?.key
      != rows.entries[position].key
  }

  private func logDroppedOnItsOwnDisplay(_ windowID: WindowID) {
    Self.log.info("window dropped - \(named(windowID)) - on its own display; tiling it")
  }

  private func tiling(_ rows: DisplayRows) -> TilingSnapshot {
    TilingSnapshot(rows: rows, displays: context.displays, gaps: context.gaps)
  }

  private func named(_ windowID: WindowID) -> String {
    WindowInfo.logName(windowID, context.registry.window(withID: windowID))
  }
}

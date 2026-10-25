import CoreGraphics
import TylerCore

/// The tiling commands, and keeping the workspaces in step with the windows that exist.
struct TilingController {
  let context: ControllerContext

  /// Every tiled window back into its slot, even ones that look to be in place.
  func retile(model: inout Model) -> Decision {
    let sync = SyncController(context: context).sync(model: &model)
    return Decision(effects: sync.effects + [.reconcile(force: true)])
  }

  func focus(_ target: ListTarget, model: inout Model) throws(Refusal) -> Decision {
    let before = context.viewSnapshot(of: model.rows)
    guard let windowID = model.rows.focused.current.focus(target) else {
      throw .error("no tiled windows")
    }
    // In a scrolling layout, focusing a window out of view scrolls to it.
    let scroll = before?.scroll(to: model.rows.focused.current).map(Effect.animate)
    return Decision(effects: (scroll.map { [$0] } ?? []) + [.focus(windowID)])
  }

  func swap(_ target: ListTarget, model: inout Model) throws(Refusal) -> Decision {
    guard model.rows.focused.current.count >= 2 else {
      throw .error("need at least two tiled windows to swap")
    }
    let before = context.viewSnapshot(of: model.rows)
    let slots = context.focusedSlots(in: model.rows)
    guard model.rows.focused.current.swap(target) else {
      throw .error("no tiled window is focused")
    }
    if let scroll = before?.scroll(to: model.rows.focused.current) {
      return Decision(effects: [.animate(scroll)])
    }
    return retiled(from: slots, model.rows, over: swapDuration)
  }

  /// The focused window leaves the stack of `tall` for its master section. The windows move as
  /// in a swap.
  func promote(model: inout Model) throws(Refusal) -> Decision {
    let slots = try slotsBeforeSectionChange(model.rows)
    guard model.rows.focused.current.promote() else {
      throw .message("already in the master section")
    }
    return retiled(from: slots, model.rows, over: swapDuration)
  }

  /// The focused window leaves the master section of `tall` for the top of its stack.
  func demote(model: inout Model) throws(Refusal) -> Decision {
    let slots = try slotsBeforeSectionChange(model.rows)
    guard model.rows.focused.current.count >= 2 else {
      throw .message("no other window to take the master's place")
    }
    guard model.rows.focused.current.demote() else { throw .message("already in the stack") }
    return retiled(from: slots, model.rows, over: swapDuration)
  }

  /// A floated window leaves the list and moves a little toward the middle of its display (see
  /// `FloatedFrame`); a window tiled again goes from where it floats into its slot. Both move
  /// with the windows that make room, over `animations.retile`. Asking for the state the window
  /// is already in changes nothing and says so.
  func setFloat(_ mode: FloatMode, model: inout Model) throws(Refusal) -> Decision {
    guard let windowID = context.registry.focusedID,
      let window = context.registry.window(withID: windowID)
    else { throw .error("no focused window") }
    let isFloated = model.bookkeeping.floated.contains(windowID)
    // A floated window that stopped being tileable (minimized, say) can still be let go.
    guard isFloated || window.isTileable else {
      throw .error("this window is never tiled, so it can't be floated")
    }
    let floats = mode == .toggle ? !isFloated : mode == .on
    guard floats != isFloated else {
      throw .message(isFloated ? "already floating" : "already tiled")
    }
    if floats {
      model.bookkeeping.floated.insert(windowID)
    } else {
      model.bookkeeping.floated.remove(windowID)
    }
    let change: FloatChange =
      floats ? .floats(windowID, from: window.frame) : .tiles(windowID, from: window.frame)
    return Decision(effects: reconcile(model: &model, change))
  }

  /// The window goes when the app reports it gone; an app may first ask to save it.
  func close() throws(Refusal) -> Decision {
    guard let windowID = context.registry.focusedID else { throw .error("no focused window") }
    return Decision(effects: [.close(windowID)])
  }

  /// Turning tiling off leaves visible windows where they are, brings parked ones back to where
  /// they were before tylerd moved them, and empties the other workspaces. Turning it back on
  /// tiles whatever is eligible now onto the current workspace, keeping the order it had. Before
  /// Accessibility permission is granted the choice is only recorded: `tiling off` then keeps
  /// tylerd from moving anything once it starts.
  func setTiling(_ mode: TilingMode, model: inout Model) -> Decision {
    let wasEnabled = model.tilingEnabled
    switch mode {
    case .on: model.tilingEnabled = true
    case .off: model.tilingEnabled = false
    case .toggle: model.tilingEnabled.toggle()
    }
    let reply = model.tilingEnabled ? "tiling on" : "tiling off"
    guard context.isRunning else {
      return Decision(
        "\(reply) once Accessibility permission is granted\n\(Refusal.permissionText)")
    }
    var effects: [Effect] = []
    if !model.tilingEnabled && wasEnabled { effects = unparkAll(model: &model) }
    if model.tilingEnabled && !wasEnabled {
      effects = SyncController(context: context).sync(model: &model).effects
      effects.append(.reconcile(force: true))
    }
    return Decision(reply, effects: effects)
  }

  /// Brings the workspaces' lists in line with the windows that exist, and lays out the current
  /// workspace only if its membership changed: when windows only left it, the others slide into
  /// their new slots over `animations.retile`. A focused window that was just assigned to a
  /// parked workspace brings that workspace into view, so keys don't go to a parked window.
  /// Windows in `held` keep their workspace wherever they are (see `SyncController.sync`).
  func reconcile(model: inout Model, holding held: Set<WindowID> = []) -> [Effect] {
    reconcile(model: &model, nil, holding: held)
  }

  /// A window the float command takes out of the focused workspace's list or puts into it.
  private enum FloatChange {
    /// From where the window is: one that sizes itself in steps (a terminal) may not quite fill
    /// its slot.
    case floats(WindowID, from: CGRect)
    case tiles(WindowID, from: CGRect)

    var joining: WindowID? {
      guard case .tiles(let windowID, _) = self else { return nil }
      return windowID
    }
  }

  /// `change` moves along with the windows that slide into their new slots.
  private func reconcile(
    model: inout Model, _ change: FloatChange?, holding held: Set<WindowID> = []
  ) -> [Effect] {
    guard context.isTiling(model) else { return [] }
    let before = model.rows
    let sync = SyncController(context: context).sync(model: &model, holding: held)
    if let (key, index) = sync.focusedArrival {
      model.rows.focus(key)
      let direction: ScrollDirection = index > model.rows.focused.currentIndex ? .next : .prev
      return sync.effects
        + WorkspaceController(context: context).show(index, direction: direction, model: &model)
    }
    guard sync.changedCurrent else { return sync.effects }
    // In a scrolling layout the view moves, so the windows jump there.
    guard model.rows.focusedWorkspaceOnlyLostWindows(since: before, apartFrom: change?.joining),
      !model.rows.focused.current.scrolls
    else { return sync.effects + [.endSlideOrSwipe, .reconcile()] }
    var slotsBefore = context.focusedSlots(in: before)
    var slotsAfter = context.focusedSlots(in: model.rows)
    switch change {
    case .floats(let windowID, let frame):
      slotsAfter +=
        floatedPlacement(of: windowID, leaving: slotsBefore, model.rows).map { [$0] } ?? []
      slotsBefore =
        slotsBefore.filter { $0.id != windowID } + [Placement(id: windowID, frame: frame)]
    case .tiles(let windowID, let frame): slotsBefore.append(Placement(id: windowID, frame: frame))
    case nil: break
    }
    let duration = Duration.milliseconds(context.config.animations.retile)
    return sync.effects + [.endSlideOrSwipe]
      + retiled(from: slotsBefore, to: slotsAfter, over: duration).effects
  }

  /// Where a window floated from one of `slots` on the focused display goes.
  private func floatedPlacement(
    of windowID: WindowID, leaving slots: [Placement], _ rows: DisplayRows
  ) -> Placement? {
    guard let slot = slots.first(where: { $0.id == windowID }),
      let display = context.display(for: rows.focusedKey)
    else { return nil }
    let area = display.visibleFrame.insetBy(dx: context.gaps.outer, dy: context.gaps.outer)
    let frame = FloatedFrame.frame(leaving: slot.frame, in: area)
    return Placement(id: windowID, frame: frame)
  }

  /// The current workspace keeps its list (so `tiling on` restores its order), and its windows
  /// in view stay where they are.
  private func unparkAll(model: inout Model) -> [Effect] {
    let offView = TilingSnapshot(rows: model.rows, displays: context.displays, gaps: context.gaps)
      .offViewWindows
    var restored: [WindowID] = []
    for position in model.rows.entries.indices {
      restored += model.rows[position].current.windows.filter(offView.contains)
      for index in model.rows[position].indices where index != model.rows[position].currentIndex {
        restored += model.rows[position][index].windows
        model.rows[position][index].sync(eligible: [])
      }
    }
    return [.restoreOriginalFrames(restored)]
  }

  private var swapDuration: Duration { .milliseconds(context.config.animations.swap) }

  /// The windows slide from `slots` into their slots now, taking `duration`.
  private func retiled(
    from slots: [Placement], _ rows: DisplayRows, over duration: Duration
  ) -> Decision {
    retiled(from: slots, to: context.focusedSlots(in: rows), over: duration)
  }

  private func retiled(
    from before: [Placement], to after: [Placement], over duration: Duration
  ) -> Decision {
    let retile = Transition(retiling: before, to: after, duration: duration)
    return Decision(effects: [retile.tracks.isEmpty ? .reconcile() : .animate(retile)])
  }

  /// The slots before a window changes section, once it is clear the focused workspace has one.
  private func slotsBeforeSectionChange(_ rows: DisplayRows) throws(Refusal) -> [Placement] {
    let workspace = rows.focused.current
    guard workspace.layout == .tall else {
      throw .error("only the tall layout has a master section")
    }
    guard workspace.focused != nil else { throw .error("no tiled window is focused") }
    return context.focusedSlots(in: rows)
  }
}

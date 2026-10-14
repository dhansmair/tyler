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
    guard model.rows.focused.current.swap(target) else {
      throw .error("no tiled window is focused")
    }
    let scroll = before?.scroll(to: model.rows.focused.current).map(Effect.animate)
    return Decision(effects: [scroll ?? .reconcile()])
  }

  /// A floated window leaves the list and stays where it is. Asking for the state the window is
  /// already in changes nothing and says so.
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
    return Decision(effects: reconcile(model: &model))
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
  /// workspace only if its membership changed. A focused window that was just assigned to a
  /// parked workspace brings that workspace into view, so keys don't go to a parked window.
  func reconcile(model: inout Model) -> [Effect] {
    guard context.isTiling(model) else { return [] }
    let sync = SyncController(context: context).sync(model: &model)
    if let (key, index) = sync.focusedArrival {
      model.rows.focus(key)
      let direction: ScrollDirection = index > model.rows.focused.currentIndex ? .next : .prev
      return sync.effects
        + WorkspaceController(context: context).show(index, direction: direction, model: &model)
    }
    return sync.effects + (sync.changedCurrent ? [.endSlideOrSwipe, .reconcile()] : [])
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
}

import TylerCore

/// The layout commands, on the focused display's current workspace: its layout, tall's master
/// ratio and the strip's window sizes.
struct LayoutController {
  let context: ControllerContext

  func setLayout(_ choice: LayoutChoice, model: inout Model) -> Decision {
    switch choice {
    case .set(let kind): model.rows.focused.current.layout = kind
    case .next: model.rows.focused.current.cycleLayout(through: context.config.layouts.cycle)
    }
    return Decision("layout \(model.rows.focused.current.layout.rawValue)", effects: [.reconcile()])
  }

  func adjustRatio(by delta: Double, model: inout Model) throws(Refusal) -> Decision {
    guard model.rows.focused.current.layout != .grid else {
      throw .message("grid has no master ratio")
    }
    guard model.rows.focused.current.update(\.tall, { tall, _ in tall.adjustRatio(by: delta) })
    else {
      let ratio = model.rows.focused.current.layoutStates.tall.mainRatio
      throw .message("master ratio is already at its limit (\(ratio))")
    }
    return Decision(effects: [.reconcile()])
  }

  /// `quarter` pairs the window with a neighbour (see `StripLayoutState.setSizeWithPartner`).
  /// Other layouts keep the size for when the workspace turns to the strip.
  func setSize(_ choice: SizeChoice, model: inout Model) throws(Refusal) -> Decision {
    guard let windowID = context.registry.focusedID,
      model.rows.focused.current.contains(windowID)
    else { throw .error("the focused window is not tiled") }
    let size =
      switch choice {
      case .set(let chosen): chosen
      case .next: model.rows.focused.current.layoutStates.strip.size(of: windowID).next
      }
    let before = context.viewSnapshot(of: model.rows)
    let change = model.rows.focused.current.update(\.strip) { strip, windows in
      strip.setSizeWithPartner(size, of: windowID, in: windows)
    }
    if change == .noPartner {
      throw .error(
        "a quarter window shares its column with the next or previous window, and neither is free")
    }
    let scroll = before?.scroll(to: model.rows.focused.current)
    let summary =
      model.rows.focused.current.layout == .strip
      ? "size \(size.rawValue)" : "size \(size.rawValue) (used by the strip layout)"
    return Decision(summary, effects: [scroll.map(Effect.animate) ?? .reconcile()])
  }
}

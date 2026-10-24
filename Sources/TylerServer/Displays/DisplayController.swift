import CoreGraphics
import TylerCore
import TylerRuntime

/// The display commands, what happens once the displays have changed, and `window list`.
struct DisplayController {
  private static let log = TylerLog(category: "manager")

  let context: ControllerContext

  /// Focuses the window that last had focus on that display's current workspace (none if it is
  /// empty). The pointer stays where it is.
  func switchDisplay(_ target: DisplayTarget, model: inout Model) throws(Refusal) -> Decision {
    guard let position = model.rows.position(of: target) else {
      throw noSuchDisplay(target, in: model.rows)
    }
    model.focusDisplay(at: position)
    return Decision("display \(position + 1)", effects: [.focusCurrentWorkspace])
  }

  /// The focused tiled window goes to another display's current workspace, in after the focused
  /// window, takes its slot at once and becomes that workspace's focused window. Without
  /// `follow` the focus stays on this display; with it, the focus goes along.
  func moveToDisplay(
    _ target: DisplayTarget, follow: Bool, model: inout Model
  ) throws(Refusal) -> Decision {
    guard let windowID = context.registry.focusedID, let source = model.rows.location(of: windowID)
    else { throw .error("the focused window is not tiled") }
    model.focusDisplay(at: source.position)
    guard let position = model.rows.position(of: target) else {
      throw noSuchDisplay(target, in: model.rows)
    }
    guard position != source.position else { throw .message("already on display \(position + 1)") }
    let row = model.rows[position]
    let effects = WorkspaceController(context: context).moveToOtherDisplay(
      windowID, number: row.number(at: row.currentIndex), follow: follow, model: &model)
    return Decision("moved to display \(position + 1)", effects: effects)
  }

  /// Moves the focused display's current workspace, with its windows, to another display, where
  /// it goes in by number, comes on screen and gets the focus. It belongs there from now on: it
  /// goes back there whenever that display is connected. The workspace on screen there before
  /// parks, and this display shows its next workspace (or the previous one at the end of the
  /// row). Refused when it is this display's only workspace. Nothing slides. Decided after a
  /// sync of its own, whose effects run whether or not the move is refused.
  func moveWorkspaceToDisplay(
    _ target: DisplayTarget, model: inout Model
  ) throws(Refusal) -> Decision {
    guard let position = model.rows.position(of: target) else {
      throw noSuchDisplay(target, in: model.rows)
    }
    let number = model.rows.focused.number(at: model.rows.focused.currentIndex)
    let hidden = model.rows[position].current.windows
    do {
      try model.rows.moveWorkspace(number: number, to: model.rows.entries[position].key)
    } catch {
      throw .error(Self.message(error, number: number, display: position + 1))
    }
    return Decision(
      "moved workspace \(number) to display \(position + 1)",
      effects: [context.parking(hidden, in: model.rows), .reconcile(), .focusCurrentWorkspace])
  }

  /// Once the displays have settled, each workspace goes to the display it now belongs on (see
  /// `DisplayRows.reassign`) and every window is placed again, parked ones included, because
  /// macOS moves windows when displays change, and also pulls parked windows back on screen.
  /// Windows tylerd missed meanwhile are looked for too.
  func displaysSettled(model: inout Model) -> [Effect] {
    guard context.isRunning else { return [] }
    let ending = [.findMissedWindows] + context.endInteractionEffects(model)
    let context = context.endingInteraction
    Self.log.info(
      "displays changed - \(context.displays.map(\.key.rawValue).joined(separator: ", "))")
    guard model.tilingEnabled else {
      model.rows.reassign(
        to: context.displays.map(\.key),
        configured: context.config.workspaceNumbers(displayCount: max(1, context.displays.count)))
      return ending
    }
    // The windows macOS moved stay on their workspaces: only windows that came or went
    // meanwhile change the lists.
    let sync = SyncController(context: context).sync(model: &model, holding: model.rows.allWindows)
    var parked: [WindowID] = []
    for position in model.rows.entries.indices {
      let row = model.rows[position]
      for index in row.indices where index != row.currentIndex {
        parked += row[index].windows
      }
    }
    return ending + sync.effects + [
      .reconcile(force: true), context.parking(parked, in: model.rows),
    ]
  }

  /// Every known window, tagged with its display, workspace, tiling slot and floated state.
  func windowList(_ model: Model) -> [WindowInfo] {
    context.registry.windows.map { window in
      var copy = window
      let display = DisplayGeometry.display(containing: window.frame, in: context.displays)
      copy.displayID = display?.id
      copy.displayNumber = display.flatMap { display in
        context.displays.firstIndex { $0.id == display.id }.map { $0 + 1 }
      }
      if let location = model.rows.location(of: window.id) {
        let row = model.rows[location.position]
        copy.workspace = row.number(at: location.index)
        copy.slot = row[location.index].slot(of: window.id)
      }
      copy.isFloated = model.bookkeeping.floated.contains(window.id)
      return copy
    }
  }

  private static func message(_ error: DisplayRows.MoveError, number: Int, display: Int) -> String {
    switch error {
    case .alreadyThere: "workspace \(number) is already on display \(display)"
    case .lastWorkspace: "workspace \(number) is the only one on its display"
    case .noSuchWorkspace: "workspace \(number) does not exist"
    case .noSuchDisplay: "display \(display) does not exist"
    }
  }

  private func noSuchDisplay(_ target: DisplayTarget, in rows: DisplayRows) -> Refusal {
    guard case .number(let number) = target else { return .error("no such display") }
    return .error(
      "display \(number) does not exist "
        + "(use \(WorkspaceController.describe(Array(1...rows.entries.count))))")
  }
}

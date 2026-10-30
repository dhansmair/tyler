import CoreGraphics
import TylerCore
import TylerRuntime

/// Switching between workspaces with a slide, and sending windows to another one.
struct WorkspaceController {
  let context: ControllerContext

  /// The target's windows slide in while the current ones slide out and park, then focus goes
  /// to the target's focused window (none if it is empty). `prev` and `next` stay on the focused
  /// display; a number on another display goes there, which then becomes the focused display.
  func switchWorkspace(
    _ target: WorkspaceTarget, model: inout Model
  ) throws(Refusal) -> Decision {
    var changedDisplay = false
    if case .number(let number) = target { changedDisplay = model.focusDisplay(holding: number) }
    guard let index = model.rows.focused.index(of: target) else {
      throw outOfRange(target, in: model.rows)
    }
    let summary = "workspace \(model.rows.focused.number(at: index))"
    guard index != model.rows.focused.currentIndex else {
      return Decision(summary, effects: changedDisplay ? [.focusCurrentWorkspace] : [])
    }
    let direction = target.direction(from: model.rows.focused.currentIndex, to: index)
    return Decision(
      summary, effects: show(index, direction: direction, model: &model) + [.focusCurrentWorkspace])
  }

  /// The focused tiled window goes to another workspace, where it becomes that workspace's
  /// focused window. Without `follow` it slides off and parks, and focus stays on this
  /// workspace; with `follow` the view switches along with it.
  func moveToWorkspace(
    _ target: WorkspaceTarget, follow: Bool, model: inout Model
  ) throws(Refusal) -> Decision {
    guard let windowID = context.registry.focusedID, model.rows.location(of: windowID) != nil
    else { throw .error("the focused window is not tiled") }
    model.focusDisplay(of: windowID, in: context)
    if case .number(let number) = target, isOnOtherDisplay(number, in: model.rows) {
      return Decision(
        "moved to workspace \(number)",
        effects: moveToOtherDisplay(windowID, number: number, follow: follow, model: &model))
    }
    guard let source = model.rows.focused.index(containing: windowID) else {
      throw .error("the focused window is not tiled")
    }
    guard let index = model.rows.focused.index(of: target) else {
      throw outOfRange(target, in: model.rows)
    }
    guard index != source else {
      throw .message("already on workspace \(model.rows.focused.number(at: index))")
    }
    let current = model.rows.focused.currentIndex
    let direction = target.direction(from: source, to: index)
    let slots = context.focusedSlots(in: model.rows)
    model.rows.focused.move(windowID, to: index)
    var effects: [Effect]
    if follow && index != current {
      effects = show(index, direction: direction, model: &model) + [.focusCurrentWorkspace]
    } else if source == current {
      effects = sendOff(windowID, towards: direction, leaving: slots, rows: model.rows)
      effects.append(.focusCurrentWorkspace)
    } else {
      effects = [.reconcile()]
    }
    return Decision("moved to workspace \(model.rows.focused.number(at: index))", effects: effects)
  }

  /// The window sent away slides off while the others slide from `slots` into their new ones
  /// over `animations.retile`, as one transition: only one runs at a time. With a zero
  /// `animations.retile`, or in a scrolling layout, the others jump once the window is off.
  private func sendOff(
    _ windowID: WindowID, towards direction: ScrollDirection, leaving slots: [Placement],
    rows: DisplayRows
  ) -> [Effect] {
    guard let departure = slideOut(windowID, towards: direction, rows: rows) else {
      return [.reconcile()]
    }
    let duration = Duration.milliseconds(context.config.animations.retile)
    let retile = Transition(
      retiling: slots, to: context.focusedSlots(in: rows), duration: duration)
    guard duration > .zero, !rows.focused.current.scrolls, !retile.tracks.isEmpty else {
      return [.animate(departure), .reconcile()]
    }
    let together = Transition(
      tracks: departure.tracks + retile.tracks, finals: departure.finals + retile.finals,
      duration: duration)
    return [.animate(together)]
  }

  /// Sends a window to workspace `number` on another display. If that workspace is on screen
  /// there, the window takes its slot at once; otherwise it parks on that display. With
  /// `follow`, that display becomes the focused one and shows the workspace.
  func moveToOtherDisplay(
    _ windowID: WindowID, number: Int, follow: Bool, model: inout Model
  ) -> [Effect] {
    let wasOnScreen =
      model.rows.focused.index(containing: windowID) == model.rows.focused.currentIndex
    guard model.rows.moveWindow(windowID, toNumber: number),
      let target = model.rows.location(ofNumber: number)
    else { return [] }
    let isOnScreen = target.index == model.rows[target.position].currentIndex
    var effects: [Effect] = isOnScreen ? [] : [context.parking([windowID], in: model.rows)]
    if follow {
      model.focusDisplay(holding: number)
      if isOnScreen {
        effects.append(.reconcile())
      } else {
        let direction: ScrollDirection =
          target.index > model.rows.focused.currentIndex ? .next : .prev
        effects += show(target.index, direction: direction, model: &model)
      }
      effects.append(.focusCurrentWorkspace)
    } else {
      effects.append(.reconcile())
      if wasOnScreen { effects.append(.focusCurrentWorkspace) }
    }
    return effects
  }

  /// How long a focus on a parked window must last before its workspace comes into view. An app
  /// with windows on two displays can report the one it remembers on its way to the one asked for
  /// (`macos-behaviour.md`, "An app's focus across displays"): the wanted window followed within
  /// 21 ms in every measured case.
  static let parkedFocusSettling: Duration = .milliseconds(60)

  /// Whether a focus on `windowID` would bring a parked workspace into view.
  func isParked(_ windowID: WindowID, in model: Model) -> Bool {
    guard context.isTiling(model), let location = model.rows.location(of: windowID) else {
      return false
    }
    return location.index != model.rows[location.position].currentIndex
  }

  /// The OS focused `windowID` (a click, cmd-tab, an app raising itself). If it lives on a
  /// parked workspace and the focus wasn't tylerd's own doing (`isEcho`), that workspace comes
  /// into view. If it is out of view in a scrolling layout on the current workspace, the view
  /// scrolls to it.
  func focusChanged(to windowID: WindowID, isEcho: Bool, model: inout Model) -> [Effect] {
    model.focusDisplay(of: windowID, in: context)
    let isTiling = context.isTiling(model)
    let before = isTiling ? context.viewSnapshot(of: model.rows) : nil
    model.recordFocus(windowID)
    let row = model.rows.focused
    let index = row.index(containing: windowID)
    if index == row.currentIndex, let scroll = before?.scroll(to: row.current) {
      return [.animate(scroll)]
    }
    guard !isEcho, isTiling, let index, index != row.currentIndex else { return [] }
    context.log.info(
      "workspace switching - \(row.number(at: index)) on display "
        + "\((model.rows.position(of: model.rows.focusedKey) ?? 0) + 1) - focus moved to "
        + WindowInfo.logName(windowID, context.registry.window(withID: windowID)))
    return show(index, direction: index > row.currentIndex ? .next : .prev, model: &model)
  }

  /// Makes the workspace at `index` of the focused display current: the current windows slide
  /// out sideways by the width of the visible frame and park, the target's slide in from the
  /// other side. Focus stays where it is: a command focuses the workspace afterwards.
  func show(_ index: Int, direction: ScrollDirection, model: inout Model) -> [Effect] {
    var effects = context.endInteractionEffects(model)
    let context = context.endingInteraction
    // Sync before switching, never after: the target's windows are parked, and a parked frame
    // can overlap a neighbouring display more than this one, which would drop them.
    effects += SyncController(context: context).sync(model: &model).effects
    guard let display = context.display(for: model.rows.focusedKey) else {
      model.rows.focused.select(index)
      return effects
    }
    let plan = slidePlan(to: index, direction: direction, on: display, rows: model.rows)
    model.rows.focused.select(index)
    effects.append(.animate(plan.transition))
    return effects
  }

  /// How the windows move when the workspace at `index` comes into view from `direction`: the
  /// current workspace's windows leave from where they are, the target's come in.
  func slidePlan(
    to index: Int, direction: ScrollDirection, on display: DisplayInfo, rows: DisplayRows
  ) -> SlidePlan {
    let row = rows.focused
    // Only windows in view leave: windows out of view in a scrolling layout are parked already.
    let leaving = row.current.placements(on: display, gaps: context.gaps).compactMap { placement in
      context.registry.window(withID: placement.id).map {
        Placement(id: placement.id, frame: $0.frame)
      }
    }
    return SlidePlan(
      to: index, direction: direction, leaving: leaving,
      entering: row[index].placements(on: display, gaps: context.gaps), on: display)
  }

  /// Slides one visible window off the display towards the workspace it was sent to, and parks
  /// it. The view stays put, so the window moves the opposite way to windows leaving when the
  /// view scrolls: one sent to the `next` workspace goes right, where that workspace comes from.
  /// On a display with a neighbour beside it, it jumps to its parking spot instead (see
  /// `SlidePlan`).
  private func slideOut(
    _ windowID: WindowID, towards direction: ScrollDirection, rows: DisplayRows
  ) -> Transition? {
    guard let display = context.display(for: rows.focusedKey),
      let frame = context.registry.window(withID: windowID)?.frame
    else { return nil }
    let parked = [Placement(id: windowID, frame: Parking.frame(for: frame, on: display))]
    let tracks: [Track] =
      display.neighbours.isEmpty
      ? [.leaving(windowID, from: frame, direction: direction.opposite, on: display)] : []
    return Transition(tracks: tracks, finals: parked)
  }

  private func isOnOtherDisplay(_ number: Int, in rows: DisplayRows) -> Bool {
    guard let location = rows.location(ofNumber: number) else { return false }
    return rows.entries[location.position].key != rows.focusedKey
  }

  private func outOfRange(_ target: WorkspaceTarget, in rows: DisplayRows) -> Refusal {
    guard case .number(let number) = target else { return .error("no such workspace") }
    let numbers = rows.entries.flatMap(\.row.numbers).sorted()
    return .error("workspace \(number) does not exist (use \(Self.describe(numbers)))")
  }

  /// "1 to 4" when the numbers follow each other, else listed ("5, 6, 9").
  static func describe(_ numbers: [Int]) -> String {
    guard let first = numbers.first, let last = numbers.last else { return "none" }
    if numbers.count > 1, last - first == numbers.count - 1 { return "\(first) to \(last)" }
    return numbers.map(String.init).joined(separator: ", ")
  }
}

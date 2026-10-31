import CoreGraphics
import TylerCore

/// Following the pointer: waiting for it to rest, and what is under it.
extension WindowManager {
  /// Starts waiting for the pointer to rest at `location`: if it hasn't moved again after
  /// `mouse.focus-delay`, the window under it gets focus, or the empty workspace under it. Only
  /// movement starts the wait, so windows sliding or re-tiling under a still pointer never take
  /// the focus from the keyboard.
  func pointerMoved(to location: CGPoint) {
    guard config.mouse.focusFollows else { return }
    pointerRest.restart(after: .milliseconds(config.mouse.focusDelay)) { [weak self] in
      self?.focusWindow(under: location)
    }
  }

  private func focusWindow(under location: CGPoint) {
    let check = pointerCheck(at: location)
    let effects = FocusFollowsMouseController(context: context).pointerRested(
      check: check, at: location, named: self.pointerLogSubject(location, check), model: &model)
    if let failure = run(effects).focusFailure {
      log.error(
        "window focusing failed - \(named(failure.windowID)) - under the pointer: "
          + failure.error.description)
    }
  }

  /// The point and the window on top there, for a log line about a pointer decision:
  /// `1355,-850 - #3 (Window Server)`.
  func pointerLogSubject(_ location: CGPoint, _ check: PointerCheck?) -> String {
    let point = "\(Int(location.x)),\(Int(location.y))"
    guard let topmost = check?.topmost else { return point }
    let tracked = registry.window(withID: topmost.id)
    return point + " - " + (tracked.map { WindowInfo.logName(topmost.id, $0) } ?? topmost.logName)
  }

  /// What `PointerCheck` needs to know about `location`, or `nil` without the window list. It asks
  /// the window server what is on top there, and whether a menu is open.
  func pointerCheck(at location: CGPoint) -> PointerCheck? {
    guard let stacking else { return nil }
    var check = PointerCheck()
    check.focusFollows = config.mouse.focusFollows
    check.isTiling = isTiling
    check.isIdle = interaction.isIdle
    check.isButtonHeld = pointer?.isPrimaryButtonDown ?? true
    check.isInsideDisplay = displays.displays.contains { $0.visibleFrame.contains(location) }
    check.isMenuOpen = stacking.isMenuOpen
    check.topmost = stacking.topmostWindow(at: location)
    check.inView = windowsInView
    check.focusedID = registry.focusedID
    check.isWorkspaceEmpty = isWorkspaceEmpty(at: location)
    return check
  }

  private func isWorkspaceEmpty(at location: CGPoint) -> Bool {
    guard let key = connectedDisplays.first(where: { $0.frame.contains(location) })?.key,
      let position = rows.position(of: key)
    else { return false }
    return rows[position].current.count == 0
  }

  /// The windows a user can see: those in their slots on each display's current workspace, and
  /// the floated ones. Not parked windows, including the strip's windows out of view.
  var windowsInView: Set<WindowID> {
    tiling.tiledWindowsInView.union(bookkeeping.floated)
  }
}

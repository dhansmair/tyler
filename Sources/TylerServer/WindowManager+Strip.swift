import CoreGraphics
import TylerCore

/// The strip layout: window sizes, and scrolling its view.
extension WindowManager {
  /// Sets the focused window's size in the strip layout. Other layouts keep it for when the
  /// workspace turns to the strip.
  public func setSize(_ choice: SizeChoice) -> Response {
    if let failure = beginCommand() { return failure }
    guard let windowID = registry.focusedID, workspaces.current.contains(windowID) else {
      return .error("the focused window is not tiled")
    }
    let size: WindowSize
    switch choice {
    case .set(let chosen): size = chosen
    case .next: size = workspaces.current.size(of: windowID).next
    }
    let snapshot = stripSnapshot()
    workspaces.current.setSize(size, of: windowID)
    let failures = scrollIfViewMoved(since: snapshot) ?? applyLayout()
    guard failures == 0 else { return outcome(failures: failures) }
    return .message(
      workspaces.current.layout == .strip
        ? "size \(size.rawValue)" : "size \(size.rawValue) (used by the strip layout)")
  }

  /// The current workspace before a change: its strip's view and every window's frame with it,
  /// so the change can be animated as a scroll. `nil` without a display.
  struct StripSnapshot {
    let display: DisplayInfo
    let view: WindowID?
    let arrangement: [Placement]
  }

  func stripSnapshot() -> StripSnapshot? {
    primaryDisplay.map { display in
      StripSnapshot(
        display: display, view: workspaces.current.firstVisible,
        arrangement: workspaces.current.arrangement(in: display.visibleFrame, gaps: gaps))
    }
  }

  /// Scrolls the strip from `snapshot` to the current workspace's view, if a change moved it.
  /// Returns how many windows could not be placed up front, or `nil` if the view didn't move
  /// (or the workspace isn't a strip) and nothing was done.
  func scrollIfViewMoved(since snapshot: StripSnapshot?) -> Int? {
    guard let snapshot, workspaces.current.layout == .strip,
      workspaces.current.firstVisible != snapshot.view
    else { return nil }
    let plan = ScrollPlan(
      from: snapshot.arrangement,
      to: workspaces.current.arrangement(in: snapshot.display.visibleFrame, gaps: gaps),
      on: snapshot.display)
    return animate(start: plan.start, tracks: plan.tracks, finals: plan.finals)
  }
}

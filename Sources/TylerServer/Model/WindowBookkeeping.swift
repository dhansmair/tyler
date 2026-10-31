import TylerCore

/// What the manager remembers about each window beyond the registry and the workspaces' lists.
/// What `WindowMover` remembers to move windows lives there; `WindowManager` forgets a closed
/// window in both at once, since window ids can be reused and a new window must not inherit an
/// old one's state.
struct WindowBookkeeping: Equatable {
  /// Windows the user took out of tiling; they stay where they are.
  var floated: Set<WindowID> = []
  /// Windows that have been on a workspace. App assignments only place windows not in here, so a
  /// window you moved, floated or minimized doesn't jump back to its app's workspace.
  var seen: Set<WindowID> = []
  /// Windows open when tylerd started. Every other window that has never been on a workspace just
  /// opened, so it joins the display the user is on.
  var foundAtStart: Set<WindowID> = []
  /// New windows that had their first focus.
  private var focusedOnce: Set<WindowID> = []

  init() {}

  /// Takes over what a previous tylerd handed over, for the windows in `known` only.
  init(restoring saved: SavedState, known: Set<WindowID>) {
    floated = Set(saved.floated).intersection(known)
    seen = saved.seenWindows.intersection(known)
  }

  /// Forgets a window that closed.
  mutating func forget(_ windowID: WindowID) {
    floated.remove(windowID)
    seen.remove(windowID)
    foundAtStart.remove(windowID)
    focusedOnce.remove(windowID)
  }

  /// Whether this is the first focus on a window that just opened. It may be on any display and
  /// about to join the focused one, so that focus says nothing about where the user is. A window
  /// that never joins a workspace, such as a dialog, gets one such focus only.
  mutating func takeFirstFocusOfNewWindow(_ windowID: WindowID) -> Bool {
    guard !floated.contains(windowID), !focusedOnce.contains(windowID),
      WorkspaceSync.Marks.isNew(windowID, seen: seen, foundAtStart: foundAtStart)
    else { return false }
    focusedOnce.insert(windowID)
    return true
  }
}

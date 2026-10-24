import TylerCore

/// What the manager remembers about each window beyond the registry and the workspaces' lists.
/// What `WindowMover` remembers to move windows lives there; `WindowManager` forgets a closed
/// window in both at once, since window ids can be reused and a new window must not inherit an
/// old one's state.
struct WindowBookkeeping: Equatable {
  /// Windows the user took out of tiling; they stay where they are.
  var floated: Set<WindowID> = []
  /// The 1-based slot each floated window had, which it goes back to when tiled again; kept
  /// until it is back in a list.
  var floatedSlots: [WindowID: Int] = [:]
  /// Windows that have been on a workspace. App assignments only place windows not in here, so a
  /// window you moved, floated or minimized doesn't jump back to its app's workspace.
  var seen: Set<WindowID> = []

  init() {}

  /// Takes over what a previous tylerd handed over, for the windows in `known` only.
  init(restoring saved: SavedState, known: Set<WindowID>) {
    floated = Set(saved.floated).intersection(known)
    floatedSlots = (saved.floatedSlots ?? []).reduce(into: [:]) { slots, saved in
      if floated.contains(saved.id) { slots[saved.id] = saved.slot }
    }
    seen = saved.seenWindows.intersection(known)
  }

  /// Forgets a window that closed.
  mutating func forget(_ windowID: WindowID) {
    floated.remove(windowID)
    floatedSlots[windowID] = nil
    seen.remove(windowID)
  }
}

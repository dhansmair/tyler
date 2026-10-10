import CoreGraphics
import TylerCore

/// What the manager remembers about each window beyond the registry and the workspaces' lists.
/// It lives in one place so a closed window is forgotten everywhere at once: window ids can be
/// reused, and a new window must not inherit an old one's state.
struct WindowBookkeeping {
  /// Windows the user took out of tiling; they stay where they are.
  var floated: Set<WindowID> = []
  /// Windows that have been on a workspace. App assignments only place windows not in here, so a
  /// window you moved, floated or minimized doesn't jump back to its app's workspace.
  var seen: Set<WindowID> = []
  /// Where each window was just before tylerd first moved it. `stop()` puts every window back
  /// there, and `tiling off` does it for parked ones.
  var originalFrames: [WindowID: CGRect] = [:]
  /// Windows tylerd asked to focus whose focus event hasn't arrived yet. That event is tylerd's own
  /// echo, so it must not be mistaken for the user switching to a parked window.
  var pendingFocus: Set<WindowID> = []

  init() {}

  /// Takes over what a previous tylerd handed over, for the windows in `known` only. Nothing is
  /// waiting for a focus event yet.
  init(restoring saved: SavedState, known: Set<WindowID>) {
    floated = Set(saved.floated).intersection(known)
    seen = saved.seenWindows.intersection(known)
    for entry in saved.originalFrames where known.contains(entry.id) {
      originalFrames[entry.id] = entry.frame
    }
  }

  /// Forgets a window that closed.
  mutating func forget(_ windowID: WindowID) {
    floated.remove(windowID)
    seen.remove(windowID)
    originalFrames[windowID] = nil
    pendingFocus.remove(windowID)
  }
}

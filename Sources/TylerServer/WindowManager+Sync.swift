import CoreGraphics
import TylerCore

/// Keeping the workspaces' lists in line with the windows that exist, and sending new windows
/// to the workspace their app is assigned to.
extension WindowManager {
  struct SyncOutcome {
    /// Whether the current workspace's list changed.
    var changedCurrent = false
    /// The parked workspace that the focused window was just assigned to, if any.
    var focusedArrival: Int?
  }

  /// Updates every workspace's list. A window stays on its workspace while it is tileable and not
  /// floated; parked and sliding windows keep their place whatever their frame says. Windows on
  /// the current workspace leave it when they move to another display. Tileable windows on the
  /// primary display that belong to no workspace join the current one, unless they have never
  /// been tiled and the config assigns their app to another workspace: then they are parked
  /// there.
  @discardableResult
  func syncWorkspaces() -> SyncOutcome {
    let connected = displays.displays
    // With no display at all (asleep, reconfiguring) nothing is decided, so parked windows
    // aren't forgotten while they are still parked.
    guard let primary = connected.first else { return SyncOutcome() }
    let isOnPrimary = { (window: WindowInfo) in
      DisplayGeometry.display(containing: window.frame, in: connected)?.id == primary.id
    }
    let isCandidate = { (window: WindowInfo) in
      window.isTileable && !self.bookkeeping.floated.contains(window.id)
    }
    let sliding = animatingWindows
    let assigned = workspaces.allWindows
    let newcomers = Dictionary(
      grouping: registry.windows.filter { window in
        !assigned.contains(window.id) && isCandidate(window) && isOnPrimary(window)
      },
      by: assignedIndex(of:))
    var outcome = SyncOutcome()
    var arrivals: [WindowID] = []
    for index in workspaces.indices {
      let isCurrent = index == workspaces.currentIndex
      var eligible = workspaces[index].windows.filter { windowID in
        guard let window = registry.window(withID: windowID), isCandidate(window) else {
          return false
        }
        return !isCurrent || sliding.contains(windowID) || isOnPrimary(window)
      }
      var joining = newcomers[index] ?? []
      if isCurrent {
        joining += newcomers[nil] ?? []
        if workspaces[index].count == 0 {
          // First fill: left to right, then top to bottom, so the layout matches the screen.
          joining.sort { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        }
      } else {
        arrivals += joining.map(\.id)
      }
      eligible += joining.map(\.id)
      if workspaces[index].sync(eligible: eligible) && isCurrent { outcome.changedCurrent = true }
    }
    bookkeeping.seen.formUnion(workspaces.allWindows)
    if let focusedID = registry.focusedID, arrivals.contains(focusedID) {
      outcome.focusedArrival = workspaces.index(containing: focusedID)
    }
    park(arrivals, on: primary)
    return outcome
  }

  /// The workspace the config assigns a window to, or `nil` for the current one: windows that
  /// have been tiled before, and apps without an assignment, go to the current workspace.
  private func assignedIndex(of window: WindowInfo) -> Int? {
    guard !bookkeeping.seen.contains(window.id),
      let number = config.assignedWorkspace(bundleID: window.bundleID, appName: window.appName),
      workspaces.indices.contains(number - 1), number - 1 != workspaces.currentIndex
    else { return nil }
    return number - 1
  }

  /// Moves windows straight to their parking spot, without a slide.
  private func park(_ windowIDs: [WindowID], on display: DisplayInfo) {
    place(
      windowIDs.compactMap { windowID in
        registry.window(withID: windowID).map { window in
          Placement(id: windowID, frame: Parking.frame(for: window.frame, on: display))
        }
      })
  }
}

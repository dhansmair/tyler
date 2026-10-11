import CoreGraphics
import TylerCore

extension WindowManager {
  // MARK: - Placing windows

  /// Whether tiling runs: permission has been granted and tiling is on.
  var isTiling: Bool { state == .running && tilingEnabled }

  /// The configured space around and between tiled windows, the same on every workspace.
  var gaps: LayoutGaps { LayoutGaps(config.gaps) }

  /// Where the current workspace's layout puts each of its windows in view; `nil` without a
  /// display.
  func currentPlacements() -> [Placement]? {
    focusedDisplay.map { workspaces.current.placements(in: $0.visibleFrame, gaps: gaps) }
  }

  /// The windows of each display's current workspace that are out of view (in the strip
  /// layout), which wait parked.
  var offViewWindows: Set<WindowID> {
    var windows: Set<WindowID> = []
    for position in rows.entries.indices {
      guard let display = display(at: position) else { continue }
      windows.formUnion(rows[position].current.offView(in: display.visibleFrame, gaps: gaps))
    }
    return windows
  }

  /// Where the current workspace's layout puts `windowID`; `nil` if it isn't tiled there or is
  /// out of view.
  func slot(of windowID: WindowID) -> Placement? {
    currentPlacements()?.first { $0.id == windowID }
  }

  /// Moves and resizes windows, returning how many could not be placed. One failing window
  /// never stops the others.
  @discardableResult
  func place(_ placements: [Placement]) -> Int {
    var failures = 0
    for placement in placements {
      rememberOriginalFrame(of: placement.id)
      do {
        try backend.setFrame(placement.frame, of: placement.id)
      } catch {
        failures += 1
        Self.log.error("cannot place window \(placement.id.rawValue): \(error.description)")
      }
    }
    return failures
  }

  /// Records where a window is before tylerd moves it for the first time.
  func rememberOriginalFrame(of windowID: WindowID) {
    guard bookkeeping.originalFrames[windowID] == nil,
      let frame = registry.window(withID: windowID)?.frame
    else { return }
    bookkeeping.originalFrames[windowID] = frame
  }

  /// Focuses a window, noting that the focus event it causes is tylerd's own doing.
  func requestFocus(_ windowID: WindowID) throws(BackendError) {
    let expectsEvent = registry.focusedID != windowID
    try backend.focus(windowID)
    if expectsEvent { bookkeeping.pendingFocus.insert(windowID) }
  }

  func outcome(failures: Int) -> Response {
    guard failures > 0 else { return .ok }
    return .message("\(failures) window\(failures == 1 ? "" : "s") could not be placed")
  }

  /// Whether a window is already within a point of where `placement` puts it.
  func isInPlace(_ placement: Placement) -> Bool {
    guard let current = registry.window(withID: placement.id)?.frame else { return false }
    return current.isClose(to: placement.frame)
  }
}

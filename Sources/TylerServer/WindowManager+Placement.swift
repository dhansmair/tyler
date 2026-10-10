import CoreGraphics
import TylerCore

extension WindowManager {
  // MARK: - Placing windows

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
    return Self.isClose(current, placement.frame)
  }

  static func isClose(_ first: CGRect, _ second: CGRect) -> Bool {
    abs(first.minX - second.minX) <= 1 && abs(first.minY - second.minY) <= 1
      && abs(first.width - second.width) <= 1 && abs(first.height - second.height) <= 1
  }
}

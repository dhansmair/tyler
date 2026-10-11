import CoreGraphics
import TylerCore

/// Restarting without losing the arrangement: a stopping tylerd hands its workspaces over as a
/// `SavedState` and leaves the windows where they are, and the next one starts from it.
extension WindowManager {
  /// Stops observing without moving any window, and returns what the next tylerd needs to carry
  /// on: a slide in progress is finished first, so the windows are where the state says. Before
  /// permission it passes on the state it was itself handed, if any.
  public func handOver() -> SavedState? {
    guard state == .running else {
      let unused = pendingRestore
      tearDown()
      return unused
    }
    finishAnimation()
    let saved = SavedState(
      rows: rows, floated: bookkeeping.floated, tilingEnabled: tilingEnabled,
      originalFrames: bookkeeping.originalFrames, seen: bookkeeping.seen)
    tearDown()
    return saved
  }

  /// Forgets every window and goes back to waiting for permission, leaving windows alone.
  func tearDown() {
    pump?.cancel()
    pump = nil
    pointerPump?.cancel()
    pointerPump = nil
    pointer?.stop()
    stopDisplays()
    endDrag()
    backend.stop()
    registry = WindowRegistry()
    rows = freshRows()
    bookkeeping = WindowBookkeeping()
    pendingRestore = nil
    state = .waitingForPermission
  }

  /// Takes over the workspaces a previous tylerd handed over, keeping only windows that still
  /// exist. Runs once the registry holds the windows and before the first reconcile, which then
  /// finds the current workspace's windows already in their slots and moves nothing. Returns
  /// whether there was anything to take over.
  func restorePending() -> Bool {
    guard let saved = pendingRestore else { return false }
    pendingRestore = nil
    let known = Set(registry.windows.map(\.id))
    rows = saved.rows(count: config.workspaces.count) { known.contains($0) }
    rows.setConfigured(configuredNumbers(config))
    bookkeeping = WindowBookkeeping(restoring: saved, known: known)
    tilingEnabled = saved.tilingEnabled
    return true
  }
}

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
      stack: workspaces, floated: floated, tilingEnabled: tilingEnabled,
      originalFrames: originalFrames)
    tearDown()
    return saved
  }

  /// Forgets every window and goes back to waiting for permission, leaving windows alone.
  func tearDown() {
    pump?.cancel()
    pump = nil
    backend.stop()
    registry = WindowRegistry()
    workspaces = WorkspaceStack(count: workspaceCount)
    applyGaps()
    floated = []
    originalFrames = [:]
    pendingFocus = []
    pendingRestore = nil
    state = .waitingForPermission
  }

  /// Takes over the workspaces a previous tylerd handed over, keeping only windows that still
  /// exist. Runs once the registry holds the windows and before the first reconcile, which then
  /// finds the current workspace's windows already in their slots and moves nothing.
  func restorePending() {
    guard let saved = pendingRestore else { return }
    pendingRestore = nil
    let known = Set(registry.windows.map(\.id))
    workspaces = saved.stack(count: workspaceCount) { known.contains($0) }
    applyGaps()
    floated = Set(saved.floated).intersection(known)
    originalFrames = [:]
    for entry in saved.originalFrames where known.contains(entry.id) {
      originalFrames[entry.id] = entry.frame
    }
    tilingEnabled = saved.tilingEnabled
  }
}

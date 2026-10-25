import CoreGraphics
import TylerCore

/// Restarting without losing the arrangement: a stopping tylerd hands its workspaces over as a
/// `SavedState` and leaves the windows where they are, and the next one starts from it.
extension WindowManager {
  /// Stops observing without moving any window, and returns what the next tylerd needs to carry
  /// on: a slide in progress is finished first, so the windows are where the state says. Before
  /// permission it passes on the state it was itself handed, if any.
  ///
  /// With `puttingWindowsBack`, every window first goes back where it was before tylerd moved it,
  /// as at `stop`, and the workspaces are still handed over: for a next tylerd under another
  /// grant, which may not have it yet and couldn't move parked windows until then.
  package func handOver(puttingWindowsBack: Bool = false) -> SavedState? {
    guard state == .running else {
      let unused = pendingRestore
      tearDown()
      return unused
    }
    endSlideOrSwipe()
    let saved = SavedState(
      rows: rows, floated: bookkeeping.floated, tilingEnabled: tilingEnabled,
      originalFrames: mover.originalFrames, seen: bookkeeping.seen,
      processIDs: Dictionary(
        registry.windows.map { ($0.id, $0.processID) }, uniquingKeysWith: { first, _ in first }))
    if puttingWindowsBack { restoreOriginalFrames(of: registry.windows.map(\.id)) }
    tearDown()
    return saved
  }

  /// Forgets every window and goes back to waiting for permission, leaving windows alone.
  func tearDown() {
    pump?.cancel()
    pump = nil
    pointerPump?.cancel()
    pointerPump = nil
    pointerRest.cancel()
    gapHover?.show(over: nil)
    pointer?.stop()
    stopDisplays()
    endDrag()
    windowSystem.stop()
    registry = WindowRegistry()
    rows = freshRows()
    bookkeeping = WindowBookkeeping()
    model.lateHandOver = LateHandOver()
    mover.reset()
    interpreter = WindowEventInterpreter()
    pendingRestore = nil
    state = .waitingForPermission
  }

  /// Parks the windows of every parked workspace that are in view: all of them after a hand-over
  /// that put the windows back, none after one that left them parked (where each keeps the size
  /// it had, so it isn't exactly at the spot a fresh parking would give it).
  func parkHandedOverWindows() {
    let displays = context.displays
    let inView = rows.windowsOnParkedWorkspaces.compactMap { registry.window(withID: $0) }
      .filter { window in !displays.contains { Parking.isParked(window.frame, on: $0) } }
    place(
      inView.compactMap { tiling.parkingPlacement(of: $0.id, size: $0.frame.size) })
  }

  /// Takes over the workspaces a previous tylerd handed over; windows not there yet get their
  /// place back when they appear (`LateHandOver`). Runs once the registry holds the windows and
  /// before the first reconcile, which then finds the current workspace's windows already in
  /// their slots and moves nothing. Returns whether there was anything to take over.
  func restorePending() -> Bool {
    guard let saved = pendingRestore else { return false }
    pendingRestore = nil
    let known = Set(registry.windows.map(\.id))
    rows = saved.rows(count: config.workspaces.count) { known.contains($0) }
    rows.newLayout = config.layouts.initial
    rows.setConfigured(configuredNumbers(config))
    bookkeeping = WindowBookkeeping(restoring: saved, known: known)
    model.lateHandOver = LateHandOver(saved, taken: known)
    mover.adopt(saved, known: known)
    tilingEnabled = saved.tilingEnabled
    return true
  }
}

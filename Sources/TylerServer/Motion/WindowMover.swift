import CoreGraphics
import TylerCore
import TylerRuntime

/// The one place that moves and focuses windows, and what it has to remember for that: where each
/// window was before tylerd first moved it, and the windows on their way to another display.
@MainActor
final class WindowMover {
  private static let log = TylerLog(category: "manager")

  private let backend: any WindowBackend
  private let displays: any DisplayProvider
  /// `stop()` puts every window back here, and `tiling off` does it for parked ones.
  private(set) var originalFrames: [WindowID: CGRect] = [:]
  /// Windows sent to another display whose move hasn't been reported back yet. Each move is
  /// reported on its own, and until then the registry still has the window on the display it
  /// left: when several windows change display at once (a workspace moved, a display plugged
  /// back in), a sync on the first report would read the others as moved back by the user.
  private(set) var crossing: Set<WindowID> = []
  private let clock: any Clock<Duration>
  private var meter: Meter?

  init(
    backend: any WindowBackend, displays: any DisplayProvider,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.backend = backend
    self.displays = displays
    self.clock = clock
  }

  /// Moves and resizes windows, returning how many could not be placed. One failing window never
  /// stops the others.
  @discardableResult
  func place(
    _ placements: [Placement], inPassing: Bool = false, known registry: WindowRegistry
  ) -> Int {
    var failures = 0
    for placement in placements {
      rememberOriginalFrame(of: placement.id, known: registry)
      noteCrossing(placement, known: registry)
      do {
        try timed(placement.id) { () throws(BackendError) in
          if inPassing {
            try backend.setFrameInPassing(placement.frame, of: placement.id)
          } else {
            try backend.setFrame(placement.frame, of: placement.id)
          }
        }
      } catch {
        failures += 1
        Self.log.error(
          "window placing failed - \(Self.named(placement.id, registry)) - \(error.description)")
      }
    }
    return failures
  }

  /// One step of a slide: a move without a resize, in a single call to the app.
  func nudge(_ windowID: WindowID, to origin: CGPoint, known registry: WindowRegistry) {
    rememberOriginalFrame(of: windowID, known: registry)
    do {
      try timed(windowID) { () throws(BackendError) in
        try backend.setPosition(origin, of: windowID)
      }
    } catch {
      // One missed frame is invisible; the final placement reports real failures.
      Self.log.debug(
        "window sliding failed - \(Self.named(windowID, registry)) - \(error.description)")
    }
  }

  /// Moves a window the user grabbed with the modifier. The user is moving it, as with a drag by
  /// its title bar, so this isn't remembered as tylerd's move.
  func carry(_ windowID: WindowID, to origin: CGPoint, known registry: WindowRegistry) {
    do {
      try timed(windowID) { () throws(BackendError) in
        try backend.setPosition(origin, of: windowID)
      }
    } catch {
      Self.log.error(
        "window moving failed - \(Self.named(windowID, registry)) - \(error.description)")
    }
  }

  /// Resizes a window the user grabbed with the modifier; see `carry`.
  func carry(_ windowID: WindowID, toFrame frame: CGRect, known registry: WindowRegistry) {
    do {
      try timed(windowID) { () throws(BackendError) in try backend.setFrame(frame, of: windowID) }
    } catch {
      Self.log.error(
        "window resizing failed - \(Self.named(windowID, registry)) - \(error.description)")
    }
  }

  /// Moves windows back to their original frames. Windows tylerd never moved are skipped.
  @discardableResult
  func restoreOriginalFrames(of windowIDs: [WindowID], known registry: WindowRegistry) -> Int {
    place(
      windowIDs.compactMap { windowID in
        originalFrames[windowID].map { Placement(id: windowID, frame: $0) }
      }, known: registry)
  }

  func focus(_ windowID: WindowID, known registry: WindowRegistry) throws(BackendError) {
    Self.log.info("window focusing - \(Self.named(windowID, registry))")
    try backend.focus(windowID)
  }

  func close(_ windowID: WindowID, known registry: WindowRegistry) throws(BackendError) {
    Self.log.info("window closing - \(Self.named(windowID, registry))")
    try backend.close(windowID)
  }

  /// Takes keyboard focus away from every window.
  func unfocus() throws(BackendError) {
    try backend.unfocus()
  }

  /// Lets go of every window still on its way to another display: a move the app refused is
  /// never reported, and the window then belongs where it is.
  func letGoOfCrossings() {
    crossing = []
  }

  func release(_ windowIDs: Set<WindowID>) {
    crossing.subtract(windowIDs)
  }

  /// Takes over the original frames a previous tylerd handed over, for the windows in `known`.
  func adopt(_ saved: SavedState, known: Set<WindowID>) {
    originalFrames = [:]
    for entry in saved.originalFrames where known.contains(entry.id) {
      originalFrames[entry.id] = entry.frame
    }
  }

  /// Forgets a window that closed. Window ids can be reused, and a new window must not inherit
  /// an old one's state.
  func forget(_ windowID: WindowID) {
    originalFrames[windowID] = nil
    crossing.remove(windowID)
  }

  /// Forgets every window.
  func reset() {
    originalFrames = [:]
    crossing = []
  }

  /// Starts adding up what the writes cost, dropping a measurement still running.
  func startMeasuring() {
    _ = backend.takeQueuedWrites()
    let clock = clock  // Swift opens the existential from a local, not from the stored property.
    meter = Meter(elapsed: Self.stopwatch(on: clock))
  }

  /// Ends the measurement, returning what it found.
  func stopMeasuring() -> MotionCost? {
    defer { meter = nil }
    meter?.cost.add(backend.takeQueuedWrites())
    return meter?.cost
  }

  /// Marks the start of a step that moves windows together: a slide's frame, a swipe's step,
  /// a drag's follow-up.
  func frameStarted() {
    guard let elapsed = meter?.elapsed else { return }
    meter?.cost.frameStarted(at: elapsed())
  }

  func windowUpdated() {
    meter?.cost.windowUpdated()
  }

  private func timed(
    _ windowID: WindowID, _ write: () throws(BackendError) -> Void
  ) throws(BackendError) {
    guard let elapsed = meter?.elapsed else { return try write() }
    let start = elapsed()
    defer { meter?.cost.wrote(windowID, taking: elapsed() - start) }
    try write()
  }

  private static func stopwatch(on clock: some Clock<Duration>) -> () -> Duration {
    let start = clock.now
    return { start.duration(to: clock.now) }
  }

  private func noteCrossing(_ placement: Placement, known registry: WindowRegistry) {
    guard let frame = registry.window(withID: placement.id)?.frame else { return }
    let connected = displays.displays
    let source = DisplayGeometry.display(containing: frame, in: connected)?.key
    let target = DisplayGeometry.display(containing: placement.frame, in: connected)?.key
    if source != target { crossing.insert(placement.id) }
  }

  /// A window found at a parking spot (left there by a tylerd that crashed or was killed) is
  /// remembered pulled back onto its display, so `stop` and `tiling off` bring it back into view.
  private func rememberOriginalFrame(of windowID: WindowID, known registry: WindowRegistry) {
    guard originalFrames[windowID] == nil, let frame = registry.window(withID: windowID)?.frame
    else { return }
    guard let display = DisplayGeometry.display(containing: frame, in: displays.displays),
      Parking.isParked(frame, on: display)
    else {
      originalFrames[windowID] = frame
      return
    }
    originalFrames[windowID] = Parking.pulledIn(frame, on: display)
  }

  private struct Meter {
    let elapsed: () -> Duration
    var cost = MotionCost()
  }

  private static func named(_ windowID: WindowID, _ registry: WindowRegistry) -> String {
    WindowInfo.logName(windowID, registry.window(withID: windowID))
  }
}

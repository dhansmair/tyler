import CoreGraphics
import MWMCore
import OSLog

/// Owns the window state, the virtual monitors and their tiling lists. Everything here runs on
/// the main actor, so no locking is needed; requests arriving on socket threads hop here through
/// `CommandRouter`. Monitor switching and restoring windows live in `WindowManager+Monitors`.
///
/// Tiling reacts only to commands and to windows appearing, disappearing, or changing whether
/// they are tileable (minimize, fullscreen). A window merely being moved or resized never
/// triggers a re-tile: that would fight the user's drags and feed on mwmd's own moves.
@MainActor
public final class WindowManager {
  public enum State: Equatable, Sendable {
    case waitingForPermission
    case running
  }

  public static let permissionMessage = """
    Accessibility permission has not been granted. Open System Settings > Privacy & Security > \
    Accessibility and enable the app that runs mwmd (for example your terminal), then try again.
    """
  public static let tilingOffMessage = "tiling is off (use `mwm tiling on`)"

  public private(set) var state: State = .waitingForPermission
  public private(set) var tilingEnabled = true

  static let log = Logger(subsystem: "mwm", category: "manager")

  // Internal rather than private so `WindowManager+Monitors` can reach them.
  var registry = WindowRegistry()
  var monitors: MonitorStack
  var floated: Set<WindowID> = []
  /// Where each window was just before mwmd first moved it. `stop()` puts every window back
  /// there, and `tiling off` does it for parked ones.
  var originalFrames: [WindowID: CGRect] = [:]
  /// Windows mwmd asked to focus whose focus event hasn't arrived yet. That event is mwmd's own
  /// echo, so it must not be mistaken for the user switching to a parked window.
  var pendingFocus: Set<WindowID> = []
  /// The slide in progress, if any.
  var animation: RunningAnimation?
  var animationCount = 0
  let animator: Animator
  let backend: any WindowBackend
  let displays: any DisplayProvider
  private let gate: any AccessibilityGate
  private let monitorCount: Int
  private var pump: Task<Void, Never>?

  public init(
    backend: any WindowBackend,
    displays: any DisplayProvider,
    gate: any AccessibilityGate,
    animator: Animator = Animator(),
    monitorCount: Int = MonitorStack.defaultCount
  ) {
    self.backend = backend
    self.displays = displays
    self.gate = gate
    self.animator = animator
    self.monitorCount = monitorCount
    monitors = MonitorStack(count: monitorCount)
  }

  // MARK: - Lifecycle

  /// Starts observing windows (and tiling them, if tiling is on) once Accessibility permission
  /// has been granted. Idempotent. Returns whether the manager is running afterwards.
  @discardableResult
  public func startIfPermitted() -> Bool {
    if state == .running { return true }
    guard gate.isTrusted else { return false }

    // Subscribe before starting so no event is lost; the registry tolerates duplicates.
    let events = backend.events
    pump = Task { [weak self] in
      for await event in events {
        self?.apply(event)
      }
    }
    backend.start()
    registry.replaceAll(backend.snapshot())
    state = .running
    reconcile()
    if let focusedID = registry.focusedID { monitors.setFocus(focusedID) }
    return true
  }

  /// Puts every window back where it was before mwmd first moved it (parked windows included),
  /// then stops observing. A window that can't be restored is logged and doesn't stop the rest.
  public func stop() {
    cancelAnimation()
    if state == .running { restoreOriginalFrames(of: registry.windows.map(\.id)) }
    pump?.cancel()
    pump = nil
    backend.stop()
    registry = WindowRegistry()
    monitors = MonitorStack(count: monitorCount)
    floated = []
    originalFrames = [:]
    pendingFocus = []
    state = .waitingForPermission
  }

  // MARK: - Requests

  public func handle(_ request: Request) -> Response {
    switch request {
    case .ping: .pong
    case .list: windows()
    case .retile: retile()
    case .tiling(let mode): setTiling(mode)
    case .focus(let target): focus(target)
    case .swap(let target): swap(target)
    case .layout(let choice): setLayout(choice)
    case .ratio(let delta): adjustRatio(by: delta)
    case .toggleFloat: toggleFloat()
    case .monitor, .moveToMonitor: handleMonitorRequest(request)
    }
  }

  /// All known windows, tagged with their display, monitor, tiling slot and floated state.
  public func windows() -> Response {
    guard state == .running else { return .error(Self.permissionMessage) }
    let connected = displays.displays
    let tagged = registry.windows.map { window -> WindowInfo in
      var copy = window
      copy.displayID = DisplayGeometry.display(containing: window.frame, in: connected)?.id
      let monitor = monitors.monitor(of: window.id)
      copy.monitor = monitor.map { $0 + 1 }
      copy.slot = monitor.flatMap { monitors[$0].slot(of: window.id) }
      copy.isFloated = floated.contains(window.id)
      return copy
    }
    return .windows(tagged)
  }

  /// Puts every tiled window back into its slot, even ones that look to be in place.
  public func retile() -> Response {
    if let failure = beginCommand() { return failure }
    syncMonitors()
    return outcome(failures: applyLayout(force: true))
  }

  /// Turning tiling off leaves visible windows where they are, brings parked ones back to where
  /// they were before mwmd moved them, and empties the other monitors. Turning it back on tiles
  /// whatever is eligible now onto the current monitor, keeping the order it had.
  public func setTiling(_ mode: TilingMode) -> Response {
    finishAnimation()
    let wasEnabled = tilingEnabled
    switch mode {
    case .on: tilingEnabled = true
    case .off: tilingEnabled = false
    case .toggle: tilingEnabled.toggle()
    }
    if !tilingEnabled && wasEnabled && state == .running {
      unparkAll()
    }
    if tilingEnabled && !wasEnabled && state == .running {
      syncMonitors()
      applyLayout(force: true)
    }
    return .message(tilingEnabled ? "tiling on" : "tiling off")
  }

  public func focus(_ target: ListTarget) -> Response {
    if let failure = beginCommand() { return failure }
    guard let windowID = monitors.current.focus(target) else { return .error("no tiled windows") }
    do {
      try requestFocus(windowID)
    } catch {
      return .error("cannot focus window \(windowID): \(error)")
    }
    return .ok
  }

  public func swap(_ target: ListTarget) -> Response {
    if let failure = beginCommand() { return failure }
    guard monitors.current.count >= 2 else {
      return .error("need at least two tiled windows to swap")
    }
    guard monitors.current.swap(target) else { return .error("no tiled window is focused") }
    return outcome(failures: applyLayout())
  }

  public func setLayout(_ choice: LayoutChoice) -> Response {
    if let failure = beginCommand() { return failure }
    switch choice {
    case .set(let kind): monitors.current.layout = kind
    case .next: monitors.current.cycleLayout()
    }
    let failures = applyLayout()
    return failures == 0
      ? .message("layout \(monitors.current.layout.rawValue)") : outcome(failures: failures)
  }

  public func adjustRatio(by delta: Double) -> Response {
    if let failure = beginCommand() { return failure }
    guard monitors.current.adjustRatio(by: delta) else {
      return .message(
        "master ratio is already at its limit (\(monitors.current.parameters.mainRatio))")
    }
    return outcome(failures: applyLayout())
  }

  /// Floats the focused window (it leaves the list and stays where it is), or tiles it again.
  public func toggleFloat() -> Response {
    if let failure = beginCommand() { return failure }
    guard let windowID = registry.focusedID, let window = registry.window(withID: windowID) else {
      return .error("no focused window")
    }
    if floated.contains(windowID) {
      floated.remove(windowID)
    } else {
      guard window.isTileable else {
        return .error("this window is never tiled, so it can't be floated")
      }
      floated.insert(windowID)
    }
    reconcile()
    return .ok
  }

  // MARK: - Events

  func apply(_ event: WindowEvent) {
    registry.apply(event)
    switch event {
    case .focused(let windowID?):
      focusChanged(to: windowID)
    case .destroyed(let windowID):
      floated.remove(windowID)
      originalFrames[windowID] = nil
      pendingFocus.remove(windowID)
    default:
      break
    }
    reconcile()
  }
}

extension WindowManager {
  // MARK: - Tiling

  /// Every command that changes windows starts here: it ends any slide in progress (jumping to
  /// its final state), then checks that tiling can run.
  func beginCommand() -> Response? {
    finishAnimation()
    guard state == .running else { return .error(Self.permissionMessage) }
    guard tilingEnabled else { return .error(Self.tilingOffMessage) }
    return nil
  }

  /// Brings the monitors' lists in line with the windows that exist, and re-lays out the
  /// current monitor only if its membership actually changed. Moves and resizes leave the lists
  /// as they are, so they do nothing.
  private func reconcile() {
    guard state == .running, tilingEnabled else { return }
    if syncMonitors() {
      finishAnimation()
      applyLayout()
    }
  }

  /// Updates every monitor's list. A window stays on its monitor while it is tileable and not
  /// floated; parked and sliding windows keep their place whatever their frame says. Windows on
  /// the current monitor leave it when they move to another display. Tileable windows on the
  /// primary display that belong to no monitor join the current one. Returns whether the
  /// current monitor's list changed.
  @discardableResult
  func syncMonitors() -> Bool {
    let connected = displays.displays
    // With no display at all (asleep, reconfiguring) nothing is decided, so parked windows
    // aren't forgotten while they are still parked.
    guard let primary = connected.first else { return false }
    let isOnPrimary = { (window: WindowInfo) in
      DisplayGeometry.display(containing: window.frame, in: connected)?.id == primary.id
    }
    let isCandidate = { (window: WindowInfo) in
      window.isTileable && !self.floated.contains(window.id)
    }
    let sliding = animatingWindows
    let assigned = monitors.allWindows
    var changedCurrent = false
    for index in monitors.indices {
      let isCurrent = index == monitors.currentIndex
      var eligible = monitors[index].windows.filter { windowID in
        guard let window = registry.window(withID: windowID), isCandidate(window) else {
          return false
        }
        return !isCurrent || sliding.contains(windowID) || isOnPrimary(window)
      }
      if isCurrent {
        var newcomers = registry.windows.filter { window in
          !assigned.contains(window.id) && isCandidate(window) && isOnPrimary(window)
        }
        if monitors[index].count == 0 {
          // First fill: left to right, then top to bottom, so the layout matches the screen.
          newcomers.sort { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        }
        eligible += newcomers.map(\.id)
      }
      if monitors[index].sync(eligible: eligible) && isCurrent { changedCurrent = true }
    }
    return changedCurrent
  }

  /// Moves every window of the current monitor to its slot, returning how many could not be
  /// placed. Windows already within a point of their slot are skipped (each move is a round
  /// trip to the app) unless `force` is set.
  @discardableResult
  func applyLayout(force: Bool = false) -> Int {
    guard let area = displays.displays.first?.visibleFrame else { return 0 }
    let placements = monitors.current.placements(in: area)
    return place(force ? placements : placements.filter { !isInPlace($0) })
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

  /// Records where a window is before mwmd moves it for the first time.
  func rememberOriginalFrame(of windowID: WindowID) {
    guard originalFrames[windowID] == nil, let frame = registry.window(withID: windowID)?.frame
    else { return }
    originalFrames[windowID] = frame
  }

  /// Focuses a window, noting that the focus event it causes is mwmd's own doing.
  func requestFocus(_ windowID: WindowID) throws(BackendError) {
    let expectsEvent = registry.focusedID != windowID
    try backend.focus(windowID)
    if expectsEvent { pendingFocus.insert(windowID) }
  }

  func outcome(failures: Int) -> Response {
    guard failures > 0 else { return .ok }
    return .message("\(failures) window\(failures == 1 ? "" : "s") could not be placed")
  }

  private func isInPlace(_ placement: Placement) -> Bool {
    guard let current = registry.window(withID: placement.id)?.frame else { return false }
    return Self.isClose(current, placement.frame)
  }

  private static func isClose(_ first: CGRect, _ second: CGRect) -> Bool {
    abs(first.minX - second.minX) <= 1 && abs(first.minY - second.minY) <= 1
      && abs(first.width - second.width) <= 1 && abs(first.height - second.height) <= 1
  }
}

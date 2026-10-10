import CoreGraphics
import OSLog
import TylerCore

/// Owns the window state, the workspaces and their tiling lists. Everything here runs on
/// the main actor, so no locking is needed; requests arriving on socket threads hop here through
/// `CommandRouter`. Workspace switching and restoring windows live in `WindowManager+Workspaces`.
///
/// Tiling reacts only to commands, to windows appearing, disappearing, or changing whether
/// they are tileable (minimize, fullscreen), and to the user resizing or dragging a tiled window
/// with the mouse (`WindowManager+Mouse`). Other moves and resizes never trigger a re-tile: that
/// would fight the user's drags and feed on tylerd's own moves.
@MainActor
public final class WindowManager {
  public enum State: Equatable, Sendable {
    case waitingForPermission
    case running
  }

  public static let permissionMessage = """
    Accessibility permission has not been granted. Open System Settings > Privacy & Security > \
    Accessibility and enable the app that runs tylerd (for example your terminal), then try again.
    """
  public static let tilingOffMessage = "tiling is off (use `tyler tiling on`)"

  public internal(set) var state: State = .waitingForPermission {
    didSet { updateIndicator() }
  }
  public internal(set) var tilingEnabled = true {
    didSet { updateIndicator() }
  }
  public internal(set) var config: Config

  static let log = Logger(subsystem: "tyler", category: "manager")

  // Internal rather than private so the `WindowManager+…` extensions can reach them.
  var registry = WindowRegistry()
  var workspaces: WorkspaceStack {
    didSet { updateIndicator() }
  }
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
  /// The slide in progress, if any.
  var animation: RunningAnimation?
  /// The trackpad pan in progress, if any (`WindowManager+Pan`).
  var pan: PanSession?
  /// While a pan is followed, the wait before its next step; `nil` when the next offset may be
  /// placed at once.
  var panThrottle: Task<Void, Never>?
  var animationCount = 0
  let animator: Animator
  let backend: any WindowBackend
  let displays: any DisplayProvider
  private let gate: any AccessibilityGate
  /// Where `reload` reads the config from; `nil` when there is nothing to reload.
  let configSource: ConfigSource?
  var pump: Task<Void, Never>?
  /// The mouse, or `nil` when tylerd doesn't follow it.
  let pointer: (any PointerInput)?
  var pointerPump: Task<Void, Never>?
  /// The window being dragged with the mouse, if any.
  var drag: MouseDrag?
  /// While a drag is followed, the wait before the next step; `nil` when the next resize may be
  /// followed at once.
  var dragThrottle: Task<Void, Never>?
  /// Times the drag steps; injected so tests don't sleep.
  let clock: any Clock<Duration>
  let indicator: (any Indicator)?
  /// What the indicator shows now, so it is only redrawn when that changes.
  var shownIndicatorState: IndicatorState?
  /// The workspaces a previous tylerd handed over, applied once windows are tracked.
  var pendingRestore: SavedState?

  public init(
    backend: any WindowBackend,
    displays: any DisplayProvider,
    gate: any AccessibilityGate,
    animator: Animator = Animator(),
    config: Config = Config(),
    configSource: ConfigSource? = nil,
    indicator: (any Indicator)? = nil,
    pointer: (any PointerInput)? = nil,
    clock: any Clock<Duration> = ContinuousClock(),
    restoring saved: SavedState? = nil
  ) {
    self.backend = backend
    self.displays = displays
    self.gate = gate
    self.animator = animator
    self.config = config
    self.configSource = configSource
    self.indicator = indicator
    self.pointer = pointer
    self.clock = clock
    pendingRestore = saved
    workspaces = WorkspaceStack(count: config.workspaces.count)
    applyGaps()
    updateIndicator()
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
    startPointer()
    registry.replaceAll(backend.snapshot())
    let restored = restorePending()
    state = .running
    reconcile()
    // A handed-over workspace beyond the configured count was merged into the last one, whose
    // windows may still be parked; every other window is in its slot already, so nothing moves.
    if restored && tilingEnabled { applyLayout() }
    if let focusedID = registry.focusedID { workspaces.setFocus(focusedID) }
    return true
  }

  /// Puts every window back where it was before tylerd first moved it (parked windows included),
  /// then stops observing. A window that can't be restored is logged and doesn't stop the rest.
  public func stop() {
    cancelAnimation()
    if state == .running { restoreOriginalFrames(of: registry.windows.map(\.id)) }
    tearDown()
  }

  /// Whether tiling is running, for `tyler status`.
  public var tilingStatus: ServerStatus.Tiling {
    guard state == .running else { return .waitingForPermission }
    return tilingEnabled ? .on : .off
  }

  // MARK: - Requests

  public func handle(_ request: Request) -> Response {
    switch request {
    case .ping: .pong
    // The process facts in a status live in `CommandRouter`, which answers it.
    case .status: .error("status is answered by the router")
    case .list: windows()
    case .reload: reload()
    case .tiling(let mode): setTiling(mode)
    case .retile, .focus, .swap, .layout, .ratio, .toggleFloat: handleTilingRequest(request)
    case .workspace, .moveToWorkspace: handleWorkspaceRequest(request)
    }
  }

  private func handleTilingRequest(_ request: Request) -> Response {
    switch request {
    case .retile: retile()
    case .focus(let target): focus(target)
    case .swap(let target): swap(target)
    case .layout(let choice): setLayout(choice)
    case .ratio(let delta): adjustRatio(by: delta)
    case .toggleFloat: toggleFloat()
    default: .error("not a tiling request")
    }
  }

  /// All known windows, tagged with their display, workspace, tiling slot and floated state.
  public func windows() -> Response {
    guard state == .running else { return .error(Self.permissionMessage) }
    let connected = displays.displays
    let tagged = registry.windows.map { window -> WindowInfo in
      var copy = window
      copy.displayID = DisplayGeometry.display(containing: window.frame, in: connected)?.id
      let workspace = workspaces.index(containing: window.id)
      copy.workspace = workspace.map { $0 + 1 }
      copy.slot = workspace.flatMap { workspaces[$0].slot(of: window.id) }
      copy.isFloated = floated.contains(window.id)
      return copy
    }
    return .windows(tagged)
  }

  /// Puts every tiled window back into its slot, even ones that look to be in place.
  public func retile() -> Response {
    if let failure = beginCommand() { return failure }
    syncWorkspaces()
    return outcome(failures: applyLayout(force: true))
  }

  /// Turning tiling off leaves visible windows where they are, brings parked ones back to where
  /// they were before tylerd moved them, and empties the other workspaces. Turning it back on tiles
  /// whatever is eligible now onto the current workspace, keeping the order it had.
  public func setTiling(_ mode: TilingMode) -> Response {
    finishAnimation()
    endDrag()
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
      syncWorkspaces()
      applyLayout(force: true)
    }
    return .message(tilingEnabled ? "tiling on" : "tiling off")
  }

  public func focus(_ target: ListTarget) -> Response {
    if let failure = beginCommand() { return failure }
    guard let windowID = workspaces.current.focus(target) else { return .error("no tiled windows") }
    do {
      try requestFocus(windowID)
    } catch {
      return .error("cannot focus window \(windowID): \(error)")
    }
    return .ok
  }

  public func swap(_ target: ListTarget) -> Response {
    if let failure = beginCommand() { return failure }
    guard workspaces.current.count >= 2 else {
      return .error("need at least two tiled windows to swap")
    }
    guard workspaces.current.swap(target) else { return .error("no tiled window is focused") }
    return outcome(failures: applyLayout())
  }

  public func setLayout(_ choice: LayoutChoice) -> Response {
    if let failure = beginCommand() { return failure }
    switch choice {
    case .set(let kind): workspaces.current.layout = kind
    case .next: workspaces.current.cycleLayout()
    }
    let failures = applyLayout()
    return failures == 0
      ? .message("layout \(workspaces.current.layout.rawValue)") : outcome(failures: failures)
  }

  public func adjustRatio(by delta: Double) -> Response {
    if let failure = beginCommand() { return failure }
    guard workspaces.current.adjustRatio(by: delta) else {
      return .message(
        "master ratio is already at its limit (\(workspaces.current.parameters.mainRatio))")
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
      if drag?.windowID == windowID { endDrag() }
      forgetPreviewTarget(windowID)
      floated.remove(windowID)
      seen.remove(windowID)
      originalFrames[windowID] = nil
      pendingFocus.remove(windowID)
    default:
      break
    }
    reconcile()
    if case .updated(let window) = event { followDrag(of: window) }
  }
}

extension WindowManager {
  // MARK: - Tiling

  /// Every command that changes windows starts here: it ends any slide in progress (jumping to
  /// its final state) and forgets any mouse drag, then checks that tiling can run.
  func beginCommand() -> Response? {
    finishAnimation()
    endDrag()
    guard state == .running else { return .error(Self.permissionMessage) }
    guard tilingEnabled else { return .error(Self.tilingOffMessage) }
    return nil
  }

  /// Brings the workspaces' lists in line with the windows that exist, and re-lays out the
  /// current workspace only if its membership actually changed. Moves and resizes leave the lists
  /// as they are, so they do nothing. A focused window that was just assigned to a parked
  /// workspace brings that workspace into view, so keys don't go to a parked window.
  private func reconcile() {
    guard state == .running, tilingEnabled else { return }
    let sync = syncWorkspaces()
    if let index = sync.focusedArrival {
      show(index, direction: index > workspaces.currentIndex ? .next : .prev, focusing: false)
    } else if sync.changedCurrent {
      finishAnimation()
      applyLayout()
    }
  }

  /// Moves every window of the current workspace to its slot, returning how many could not be
  /// placed. Windows already within a point of their slot are skipped (each move is a round
  /// trip to the app) unless `force` is set.
  @discardableResult
  func applyLayout(force: Bool = false) -> Int {
    guard let area = displays.displays.first?.visibleFrame else { return 0 }
    let placements = workspaces.current.placements(in: area)
    return place(force ? placements : placements.filter { !isInPlace($0) })
  }
}

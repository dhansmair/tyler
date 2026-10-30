import CoreGraphics
import TylerConfig
import TylerCore
import TylerProtocol
import TylerRuntime

/// Owns the window state, the workspaces and their tiling lists, and connects the parts: this
/// file holds starting, stopping and the window events; each feature's commands and how it
/// carries out its decisions are in the feature's folder. Everything here runs on the main
/// actor, so no locking is needed; requests arriving on socket threads hop here through
/// `CommandRouter`.
///
/// Tiling reacts only to commands, to windows appearing, disappearing, or changing whether
/// they are tileable (minimize, fullscreen), and to the user resizing or dragging a tiled window
/// with the mouse (`WindowManager+Drag`). Other moves and resizes never trigger a re-tile: that
/// would fight the user's drags and feed on tylerd's own moves.
@MainActor
package final class WindowManager {
  package enum State: Equatable, Sendable {
    case waitingForPermission
    case running
  }

  nonisolated package static let permissionMessage = Refusal.permissionText
  nonisolated package static let tilingOffMessage = Refusal.tilingOffText

  package internal(set) var state: State = .waitingForPermission {
    didSet { updateIndicator() }
  }
  package internal(set) var config: Config {
    didSet {
      updateIndicator()
      logOutput.level = config.log.level
    }
  }
  /// Where the log's lines go besides the unified log; tests give the manager one of its own.
  let logOutput: LogOutput
  /// The settings `config set` changed since the config was last read, by name, in the order
  /// they were first changed.
  package internal(set) var configChanges: [String] = []

  let log: TylerLog

  var model: Model {
    didSet { updateIndicator() }
  }
  var rows: DisplayRows {
    get { model.rows }
    _modify { yield &model.rows }
  }
  var bookkeeping: WindowBookkeeping {
    get { model.bookkeeping }
    _modify { yield &model.bookkeeping }
  }
  package internal(set) var tilingEnabled: Bool {
    get { model.tilingEnabled }
    set { model.tilingEnabled = newValue }
  }
  // Internal rather than private so the `WindowManager+…` extensions can reach it.
  var registry = WindowRegistry()
  var interpreter = WindowEventInterpreter()
  let mover: WindowMover
  /// The slide, swipe or drag in progress, if any (see `Interaction`).
  var interaction = Interaction.idle {
    didSet {
      if interaction.isIdle != oldValue.isIdle { refreshGapCursor() }
    }
  }
  var slideCount = 0
  let animator: Animator
  let windowSystem: any WindowSystem
  let displays: any DisplayProvider
  private let gate: any AccessibilityGate
  private let screenLock: (any ScreenLock)?
  var isScreenLocked: Bool { screenLock?.isLocked ?? false }
  /// What the last check before tracking windows found; `nil` before the first.
  private var accessBeforeStart: WindowAccess?
  /// Where `reload` reads the config from; `nil` when there is nothing to reload.
  let configSource: ConfigSource?
  var pump: Task<Void, Never>?
  /// The mouse, or `nil` when tylerd doesn't follow it.
  let pointer: (any PointerInput)?
  var pointerPump: Task<Void, Never>?
  /// Finds the window under the pointer, or `nil` when focus doesn't follow the mouse.
  let stacking: (any WindowStacking)?
  /// The resize cursor over the gap under the pointer, or `nil` when there is none to show.
  let gapHover: GapHover?
  /// Waits for the pointer to rest before focus follows it (see `pointerMoved(to:)`).
  let pointerRest: Debounce
  /// Waits for a focus on a parked window to last (see `followFocus(to:isEcho:)`).
  let parkedFocus: Debounce
  /// Follows `displays.changes` while running.
  var displayPump: Task<Void, Never>?
  /// Waits for the displays to settle after a change (see `displaysChanged`).
  let displaySettling: Debounce
  /// Paces drag and swipe steps; injected so tests don't sleep.
  let clock: any Clock<Duration>
  let indicator: (any Indicator)?
  /// What the indicator was last shown, so it is only told again when that changes.
  var shownSnapshot: IndicatorSnapshot?
  /// The workspaces a previous tylerd handed over, applied once windows are tracked.
  var pendingRestore: SavedState?

  package init(
    windowSystem: any WindowSystem,
    displays: any DisplayProvider,
    gate: any AccessibilityGate,
    screenLock: (any ScreenLock)? = nil,
    animator: Animator = Animator(),
    config: Config = Config(),
    configSource: ConfigSource? = nil,
    indicator: (any Indicator)? = nil,
    pointer: (any PointerInput)? = nil,
    stacking: (any WindowStacking)? = nil,
    gapCursor: (any GapCursor)? = nil,
    clock: any Clock<Duration> = ContinuousClock(),
    logOutput: LogOutput = .shared,
    restoring saved: SavedState? = nil
  ) {
    self.windowSystem = windowSystem
    log = TylerLog(category: "manager", output: logOutput)
    mover = WindowMover(windowSystem: windowSystem, displays: displays, clock: clock, log: log)
    self.displays = displays
    self.gate = gate
    self.screenLock = screenLock
    self.animator = animator
    self.config = config
    self.logOutput = logOutput
    logOutput.level = config.log.level
    self.configSource = configSource
    self.indicator = indicator
    self.pointer = pointer
    self.stacking = stacking
    gapHover = gapCursor.map(GapHover.init(cursor:))
    self.clock = clock
    pointerRest = Debounce(clock: clock)
    displaySettling = Debounce(clock: clock)
    parkedFocus = Debounce(clock: clock)
    pendingRestore = saved
    model = Model(
      rows: DisplayRows(
        keys: DisplayArrangement.ordered(displays.displays).map(\.key),
        configured: Self.configuredNumbers(config, displayCount: displays.displays.count),
        newLayout: config.layouts.initial))
    updateIndicator()
  }

  // MARK: - Lifecycle

  /// Starts observing windows (and tiling them, if tiling is on) once Accessibility permission
  /// has been granted. Idempotent. Returns whether the manager is running afterwards.
  @discardableResult
  package func startIfPermitted() -> Bool {
    if state == .running { return true }
    guard checkAccess() == .ok else { return false }

    // Subscribe before starting so no event is lost; the registry tolerates duplicates.
    let events = windowSystem.events
    pump = Task { [weak self] in
      for await event in events {
        self?.apply(event)
      }
    }
    windowSystem.start()
    startPointer()
    startDisplays()
    registry.replaceAll(windowSystem.snapshot())
    let restored = restorePending()
    state = .running
    // The first sync holds the handed-over windows: one put back on another display than its
    // workspace's (`handOver(puttingWindowsBack:)`) keeps its workspace, while windows that went
    // away or were minimized meanwhile leave. Then every window goes to its slot or its parking
    // spot; after a hand-over that left them in place, nothing moves here but the windows of a
    // workspace beyond the configured count, merged into the last one.
    reconcile(holding: restored ? rows.allWindows : [])
    if restored && tilingEnabled {
      reconcileWindows()
      parkHandedOverWindows()
    }
    if let focusedID = registry.focusedID {
      model.focusDisplay(of: focusedID, in: context)
      model.recordFocus(focusedID)
    }
    return true
  }

  /// Follows the Accessibility permission until cancelled, checking every `interval` and at each
  /// hint from the gate: starts once it is granted, so the user doesn't have to restart tylerd,
  /// and calls `started`. When it goes away, every event tap is removed at once, since macOS can
  /// stop all input when a process with an active tap loses the permission (see "Events and
  /// taps" in `devdocs/macos-behaviour.md`); the windows stay where they are, and tylerd carries
  /// on with its workspaces once the permission is back.
  package func followPermission(
    checkingEvery interval: Duration = .seconds(1),
    started: @escaping @MainActor @Sendable () -> Void
  ) async {
    let clock = clock  // Swift opens the existential from a local, not from the stored property.
    let hints = gate.changes
    let following = Task { @MainActor [weak self] in
      for await _ in hints { self?.checkPermission(started: started) }
    }
    defer { following.cancel() }
    while true {
      checkPermission(started: started)
      do { try await clock.sleep(for: interval) } catch { return }
    }
  }

  /// Whether tylerd may start tracking windows, logging when the reason it may not changes. The
  /// first check is logged by tylerd's start instead.
  private func checkAccess() -> WindowAccess {
    let access = WindowAccess.beforeStart(gate.facts)
    defer { accessBeforeStart = access }
    guard let previous = accessBeforeStart, previous != access else { return access }
    switch access {
    case .refused:
      log.warning(
        "permission refused - Accessibility calls fail although the permission is on")
    case .screenLocked: log.info("screen locked - windows tracking waits for it")
    case .notTrusted: log.info("permission waiting - Accessibility")
    case .ok, .checking, .blind: break
    }
    return access
  }

  private func checkPermission(started: () -> Void) {
    switch state {
    case .waitingForPermission:
      if startIfPermitted() { started() }
    case .running:
      guard !gate.isTrusted else { return }
      log.warning("permission lost - Accessibility - event taps removed, waiting for it again")
      pendingRestore = handOver()
      accessBeforeStart = .notTrusted
    }
  }

  /// Puts every window back where it was before tylerd first moved it (parked windows included),
  /// then stops observing. A window that can't be restored is logged and doesn't stop the rest.
  package func stop() {
    cancelSlide()
    forgetSwipe()
    if state == .running { restoreOriginalFrames(of: registry.windows.map(\.id)) }
    tearDown()
  }

  /// Whether tiling is running, for `tyler status`.
  package var tilingStatus: ServerStatus.Tiling {
    guard state == .running else { return .waitingForPermission }
    return tilingEnabled ? .on : .off
  }

  /// Whether tylerd can reach the windows, for `tyler status`: before it tracks them, why it
  /// doesn't; once it does, whether it sees the windows the window server shows.
  package var access: WindowAccess {
    guard state == .running else { return accessBeforeStart ?? .notTrusted }
    return WindowAccess.whileRunning(
      onScreen: stacking?.appWindowsOnScreen ?? [], known: Set(registry.windows.map(\.id)),
      isAttaching: windowSystem.isAttaching)
  }

  /// The event listeners in place, for `tyler status`.
  package var inputListeners: [InputListener] { pointer?.listeners ?? [] }

  // MARK: - Requests

  /// Every switch over requests lists every case, with no `default:`, so the compiler points at
  /// each one a new request must be added to. (It is split in four to stay within SwiftLint's
  /// complexity limit.)
  package func handle(_ request: Request) -> Response {
    switch request {
    case .ping: .pong
    // `CommandRouter` answers these: it holds the process facts and how tylerd opens an editor.
    case .status, .configEdit: .error("\(request) is answered by the router")
    case .list: windows()
    case .close: closeWindow()
    case .reload, .configGet, .configSet: handleConfigRequest(request)
    case .tiling(let mode): setTiling(mode)
    case .retile, .focus, .swap, .promote, .demote, .layout, .size, .ratio, .float:
      handleTilingRequest(request)
    case .workspace, .moveToWorkspace: handleWorkspaceRequest(request)
    case .display, .moveToDisplay, .moveWorkspaceToDisplay: handleDisplayRequest(request)
    case .debugAt, .debugWindows: handleDebugRequest(request)
    }
  }

  // MARK: - Events

  func apply(_ event: WindowEvent) {
    var known: WindowInfo?
    if case .updated(let window) = event {
      known = registry.window(withID: window.id)
      mover.windowUpdated()
    }
    registry.apply(event)
    for intent in interpreter.intents(for: event, known: known, displays: displays.displays) {
      apply(intent)
    }
  }

  private func apply(_ intent: WindowEventInterpreter.Intent) {
    switch intent {
    case .moved(let window, let previous):
      followDrag(of: window, from: previous)
    case .listsMayHaveChanged:
      reconcile()
    case .focused(let windowID, let isEcho):
      log.debug(
        "window focused - \(named(windowID)) - "
          + (isEcho ? "tylerd's own focus coming back" : "not tylerd's own"))
      followFocus(to: windowID, isEcho: isEcho)
    case .closed(let windowID):
      if drag?.windowID == windowID { endDrag() }
      forgetMovePreview()
      bookkeeping.forget(windowID)
      mover.forget(windowID)
    }
  }

  func reconcile(holding held: Set<WindowID> = []) {
    guard isTiling else { return }
    run(tilingController.reconcile(model: &model, holding: held))
  }

}

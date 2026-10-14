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

  static let log = TylerLog(category: "manager")

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
  let backend: any WindowBackend
  let displays: any DisplayProvider
  private let gate: any AccessibilityGate
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
    backend: any WindowBackend,
    displays: any DisplayProvider,
    gate: any AccessibilityGate,
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
    self.backend = backend
    mover = WindowMover(backend: backend, displays: displays, clock: clock)
    self.displays = displays
    self.gate = gate
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
    startDisplays()
    registry.replaceAll(backend.snapshot())
    let restored = restorePending()
    state = .running
    reconcile()
    // A handed-over workspace beyond the configured count was merged into the last one, whose
    // windows may still be parked; every other window is in its slot already, so nothing moves.
    if restored && tilingEnabled { reconcileWindows() }
    if let focusedID = registry.focusedID {
      model.focusDisplay(of: focusedID, in: context)
      model.recordFocus(focusedID)
    }
    return true
  }

  /// Starts as soon as Accessibility permission is granted, checking every `interval`, so the
  /// user doesn't have to restart tylerd after granting it. Returns whether it started: `false`
  /// only when the waiting task was cancelled.
  package func startWhenPermitted(checkingEvery interval: Duration = .seconds(1)) async -> Bool {
    let clock = clock  // Swift opens the existential from a local, not from the stored property.
    while !startIfPermitted() {
      do {
        try await clock.sleep(for: interval)
      } catch {
        return false
      }
    }
    return true
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
    case .retile, .focus, .swap, .layout, .size, .ratio, .float:
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
    case .moved(let window):
      followDrag(of: window)
    case .listsMayHaveChanged:
      reconcile()
    case .focused(let windowID, let isEcho):
      run(workspaceController.focusChanged(to: windowID, isEcho: isEcho, model: &model))
    case .closed(let windowID):
      if drag?.windowID == windowID { endDrag() }
      forgetPreviewTarget(windowID)
      bookkeeping.forget(windowID)
      mover.forget(windowID)
    }
  }

  func reconcile() {
    guard isTiling else { return }
    run(tilingController.reconcile(model: &model))
  }

}

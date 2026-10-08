import CoreGraphics
import MWMCore
import OSLog

/// Owns the window state and the tiling list. Everything here runs on the main actor, so no
/// locking is needed; requests arriving on socket threads hop here through `CommandRouter`.
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

  private static let log = Logger(subsystem: "mwm", category: "manager")

  private var registry = WindowRegistry()
  private var workspace = Workspace()
  private var floated: Set<WindowID> = []
  private let backend: any WindowBackend
  private let displays: any DisplayProvider
  private let gate: any AccessibilityGate
  private var pump: Task<Void, Never>?

  public init(
    backend: any WindowBackend,
    displays: any DisplayProvider,
    gate: any AccessibilityGate
  ) {
    self.backend = backend
    self.displays = displays
    self.gate = gate
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
    if let focusedID = registry.focusedID { workspace.setFocus(focusedID) }
    return true
  }

  public func stop() {
    pump?.cancel()
    pump = nil
    backend.stop()
    registry = WindowRegistry()
    workspace = Workspace()
    floated = []
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
    }
  }

  /// All known windows, tagged with their display, tiling slot and floated state.
  public func windows() -> Response {
    guard state == .running else { return .error(Self.permissionMessage) }
    let connected = displays.displays
    let tagged = registry.windows.map { window -> WindowInfo in
      var copy = window
      copy.displayID = DisplayGeometry.display(containing: window.frame, in: connected)?.id
      copy.slot = workspace.slot(of: window.id)
      copy.isFloated = floated.contains(window.id)
      return copy
    }
    return .windows(tagged)
  }

  /// Puts every tiled window back into its slot, even ones that look to be in place.
  public func retile() -> Response {
    if let failure = requireTiling() { return failure }
    workspace.sync(eligible: eligibleWindows())
    return outcome(failures: applyLayout(force: true))
  }

  /// Turning tiling off leaves windows where they are. Turning it back on tiles whatever is
  /// eligible now, keeping the order of windows that were already in the list.
  public func setTiling(_ mode: TilingMode) -> Response {
    let wasEnabled = tilingEnabled
    switch mode {
    case .on: tilingEnabled = true
    case .off: tilingEnabled = false
    case .toggle: tilingEnabled.toggle()
    }
    if tilingEnabled && !wasEnabled && state == .running {
      workspace.sync(eligible: eligibleWindows())
      applyLayout(force: true)
    }
    return .message(tilingEnabled ? "tiling on" : "tiling off")
  }

  public func focus(_ target: ListTarget) -> Response {
    if let failure = requireTiling() { return failure }
    guard let windowID = workspace.focus(target) else { return .error("no tiled windows") }
    do {
      try backend.focus(windowID)
    } catch {
      return .error("cannot focus window \(windowID): \(error)")
    }
    return .ok
  }

  public func swap(_ target: ListTarget) -> Response {
    if let failure = requireTiling() { return failure }
    guard workspace.count >= 2 else { return .error("need at least two tiled windows to swap") }
    guard workspace.swap(target) else { return .error("no tiled window is focused") }
    return outcome(failures: applyLayout())
  }

  public func setLayout(_ choice: LayoutChoice) -> Response {
    if let failure = requireTiling() { return failure }
    switch choice {
    case .set(let kind): workspace.layout = kind
    case .next: workspace.cycleLayout()
    }
    let failures = applyLayout()
    return failures == 0
      ? .message("layout \(workspace.layout.rawValue)") : outcome(failures: failures)
  }

  public func adjustRatio(by delta: Double) -> Response {
    if let failure = requireTiling() { return failure }
    guard workspace.adjustRatio(by: delta) else {
      return .message("master ratio is already at its limit (\(workspace.parameters.mainRatio))")
    }
    return outcome(failures: applyLayout())
  }

  /// Floats the focused window (it leaves the list and stays where it is), or tiles it again.
  public func toggleFloat() -> Response {
    if let failure = requireTiling() { return failure }
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
    case .focused(let windowID?): workspace.setFocus(windowID)
    case .destroyed(let windowID): floated.remove(windowID)
    default: break
    }
    reconcile()
  }

  // MARK: - Tiling

  private func requireTiling() -> Response? {
    guard state == .running else { return .error(Self.permissionMessage) }
    guard tilingEnabled else { return .error(Self.tilingOffMessage) }
    return nil
  }

  /// Brings the tiling list in line with the windows that exist, and re-lays them out only if
  /// membership actually changed. Moves and resizes leave the list as it is, so they do nothing.
  private func reconcile() {
    guard state == .running, tilingEnabled else { return }
    if workspace.sync(eligible: eligibleWindows()) {
      applyLayout()
    }
  }

  /// Windows that should be tiled right now: tileable, not floated, on the primary display.
  private func eligibleWindows() -> [WindowID] {
    let connected = displays.displays
    guard let primary = connected.first else { return [] }
    var candidates = registry.windows.filter { window in
      window.isTileable
        && !floated.contains(window.id)
        && DisplayGeometry.display(containing: window.frame, in: connected)?.id == primary.id
    }
    if workspace.count == 0 {
      // First fill: left to right, then top to bottom, so the layout matches what is on screen.
      candidates.sort { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }
    return candidates.map(\.id)
  }

  /// Moves every tiled window to its slot, returning how many could not be placed. Windows
  /// already within a point of their slot are skipped (each move is a round trip to the app)
  /// unless `force` is set. One failing window never stops the others.
  @discardableResult
  private func applyLayout(force: Bool = false) -> Int {
    guard let area = displays.displays.first?.visibleFrame else { return 0 }
    var failures = 0
    for placement in workspace.placements(in: area) {
      if !force && isInPlace(placement) { continue }
      do {
        try backend.setFrame(placement.frame, of: placement.id)
      } catch {
        failures += 1
        Self.log.error("cannot place window \(placement.id.rawValue): \(error.description)")
      }
    }
    return failures
  }

  private func outcome(failures: Int) -> Response {
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

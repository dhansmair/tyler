import MWMCore

/// Owns the window state. Everything here runs on the main actor, so no locking is needed;
/// requests arriving on socket threads hop here through `CommandRouter`.
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

  public private(set) var state: State = .waitingForPermission

  private var registry = WindowRegistry()
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

  /// Starts observing windows if Accessibility permission has been granted. Idempotent.
  /// Returns whether the manager is running afterwards.
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
    return true
  }

  public func stop() {
    pump?.cancel()
    pump = nil
    backend.stop()
    registry = WindowRegistry()
    state = .waitingForPermission
  }

  /// All known windows, tagged with the display they are on.
  public func windows() -> Response {
    guard state == .running else { return .error(Self.permissionMessage) }
    let connected = displays.displays
    let tagged = registry.windows.map { window -> WindowInfo in
      var copy = window
      copy.displayID = DisplayGeometry.display(containing: window.frame, in: connected)?.id
      return copy
    }
    return .windows(tagged)
  }

  func apply(_ event: WindowEvent) {
    registry.apply(event)
  }
}

import AppKit
import ApplicationServices
import OSLog
import TylerCore
import TylerServer

/// The real `WindowBackend`: discovers windows through the Accessibility API and keeps the list
/// current from AX notifications and `NSWorkspace` app launch/quit/activate events.
@MainActor
public final class AXBackend: WindowBackend {
  public let events: AsyncStream<WindowEvent>

  private static let log = Logger(subsystem: "tyler", category: "ax")
  private static let maxAttachAttempts = 6
  private static let retryDelay = Duration.milliseconds(500)

  private let continuation: AsyncStream<WindowEvent>.Continuation
  private var observers: [pid_t: AppObserver] = [:]
  private var retries: [pid_t: Task<Void, Never>] = [:]
  private var elements: [WindowID: AXUIElement] = [:]
  private var owners: [WindowID: pid_t] = [:]
  private var focusedID: WindowID?
  private var workspaceTokens: [any NSObjectProtocol] = []
  private var isStarted = false

  public init() {
    (events, continuation) = AsyncStream.makeStream(of: WindowEvent.self)
  }

  // MARK: - WindowBackend

  public func start() {
    guard !isStarted else { return }
    isStarted = true
    subscribeToWorkspace()
    for app in NSWorkspace.shared.runningApplications {
      attach(processID: app.processIdentifier, attempt: 1)
    }
    updateFocusFromFrontmostApp()
  }

  public func stop() {
    guard isStarted else { return }
    isStarted = false
    let center = NSWorkspace.shared.notificationCenter
    for token in workspaceTokens { center.removeObserver(token) }
    workspaceTokens = []
    for retry in retries.values { retry.cancel() }
    retries = [:]
    for observer in observers.values { observer.stop() }
    observers = [:]
    elements = [:]
    owners = [:]
    focusedID = nil
  }

  public func snapshot() -> [WindowInfo] {
    elements.keys.sorted().compactMap { windowInfo(for: $0) }
  }

  public func setFrame(_ frame: CGRect, of windowID: WindowID) throws(BackendError) {
    guard let element = elements[windowID] else { throw .windowGone(windowID) }
    try check(AXBridge.setFrame(frame, of: element), for: windowID, action: "move")
    // The app may have clamped the size; tell the manager what it really is.
    if let info = windowInfo(for: windowID) {
      continuation.yield(.updated(info))
    }
  }

  public func setPosition(_ origin: CGPoint, of windowID: WindowID) throws(BackendError) {
    guard let element = elements[windowID] else { throw .windowGone(windowID) }
    try check(AXBridge.setPosition(origin, of: element), for: windowID, action: "move")
  }

  public func focus(_ windowID: WindowID) throws(BackendError) {
    guard let element = elements[windowID], let processID = owners[windowID] else {
      throw .windowGone(windowID)
    }
    try check(AXBridge.raise(window: element, in: processID), for: windowID, action: "focus")
  }

  /// Makes tylerd frontmost. It has no windows, so keys go nowhere until the user or a command
  /// focuses a window again.
  public func unfocus() throws(BackendError) {
    let status = AXBridge.makeFrontmost(processID: ProcessInfo.processInfo.processIdentifier)
    guard status == .success else {
      throw .refused("cannot take focus away: AX error \(status.rawValue)")
    }
    setFocus(nil)
  }

  private func check(
    _ status: AXError,
    for windowID: WindowID,
    action: String
  ) throws(BackendError) {
    switch status {
    case .success:
      return
    case .invalidUIElement:
      // The window closed under us; the destroy notification will tidy the bookkeeping.
      throw .windowGone(windowID)
    default:
      throw .refused("cannot \(action) window \(windowID): AX error \(status.rawValue)")
    }
  }

  // MARK: - Apps

  private func subscribeToWorkspace() {
    let center = NSWorkspace.shared.notificationCenter
    let names: [(Notification.Name, @MainActor (AXBackend, pid_t) -> Void)] = [
      (NSWorkspace.didLaunchApplicationNotification, { $0.attach(processID: $1, attempt: 1) }),
      (NSWorkspace.didTerminateApplicationNotification, { $0.detach(processID: $1) }),
      (NSWorkspace.didActivateApplicationNotification, { $0.appActivated(processID: $1) }),
    ]
    for (name, action) in names {
      let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard let processID = app?.processIdentifier else { return }
        MainActor.assumeIsolated {
          guard let self else { return }
          action(self, processID)
        }
      }
      workspaceTokens.append(token)
    }
  }

  private func attach(processID: pid_t, attempt: Int) {
    guard isStarted, observers[processID] == nil,
      processID != ProcessInfo.processInfo.processIdentifier,
      let app = NSRunningApplication(processIdentifier: processID),
      app.activationPolicy == .regular
    else { return }

    let application = AXBridge.applicationElement(processID: processID)
    do {
      let observer = try AppObserver(
        processID: processID,
        applicationElement: application
      ) { [weak self] notification, element in
        self?.handle(notification, element: element, processID: processID)
      }
      observers[processID] = observer
      retries[processID] = nil
      for window in AXBridge.windows(of: application) {
        register(window: window, processID: processID)
      }
    } catch {
      let name = app.localizedName ?? String(processID)
      Self.log.debug("cannot observe \(name) (attempt \(attempt)): \(String(describing: error))")
      scheduleRetry(processID: processID, attempt: attempt)
    }
  }

  /// A freshly launched app often refuses AX for a moment; try again shortly.
  private func scheduleRetry(processID: pid_t, attempt: Int) {
    guard attempt < Self.maxAttachAttempts else {
      Self.log.notice("giving up on process \(processID) after \(attempt) attempts")
      retries[processID] = nil
      return
    }
    retries[processID]?.cancel()
    retries[processID] = Task { [weak self] in
      do {
        try await Task.sleep(for: Self.retryDelay)
      } catch {
        return  // Cancelled by stop() or a newer retry; nothing left to do.
      }
      self?.attach(processID: processID, attempt: attempt + 1)
    }
  }

  private func detach(processID: pid_t) {
    retries[processID]?.cancel()
    retries[processID] = nil
    observers[processID]?.stop()
    observers[processID] = nil
    for (windowID, owner) in owners where owner == processID {
      forget(windowID)
    }
  }

  private func appActivated(processID: pid_t) {
    guard observers[processID] != nil else { return }
    let application = AXBridge.applicationElement(processID: processID)
    let windowID = AXBridge.focusedWindow(of: application).flatMap { window in
      register(window: window, processID: processID)
    }
    setFocus(windowID)
  }

  private func updateFocusFromFrontmostApp() {
    guard let front = NSWorkspace.shared.frontmostApplication else { return }
    appActivated(processID: front.processIdentifier)
  }

  // MARK: - Windows

  /// Starts tracking `window` if it's new. Returns its id, or `nil` if it has none.
  @discardableResult
  private func register(window: AXUIElement, processID: pid_t) -> WindowID? {
    guard let windowID = AXBridge.windowID(of: window) else { return nil }
    guard elements[windowID] == nil else { return windowID }
    guard let observer = observers[processID] else { return nil }

    elements[windowID] = window
    owners[windowID] = processID
    for failure in observer.observe(window: window) {
      Self.log.debug(
        "window \(windowID.rawValue) will not update live: \(String(describing: failure))")
    }
    if let info = windowInfo(for: windowID) {
      continuation.yield(.created(info))
    }
    return windowID
  }

  private func forget(_ windowID: WindowID) {
    guard elements.removeValue(forKey: windowID) != nil else { return }
    owners[windowID] = nil
    if focusedID == windowID { focusedID = nil }
    continuation.yield(.destroyed(windowID))
  }

  private func setFocus(_ windowID: WindowID?) {
    guard focusedID != windowID else { return }
    focusedID = windowID
    continuation.yield(.focused(windowID))
  }

  private func handle(_ notification: String, element: AXUIElement, processID: pid_t) {
    switch notification {
    case kAXWindowCreatedNotification:
      register(window: element, processID: processID)
    case kAXFocusedWindowChangedNotification:
      setFocus(register(window: element, processID: processID))
    case kAXUIElementDestroyedNotification:
      // The element is already invalid, so it can't be asked for its id; find it by identity.
      if let windowID = identify(element) {
        forget(windowID)
      }
    default:
      // Moved, resized, minimized, deminimized, title changed.
      guard let windowID = AXBridge.windowID(of: element) ?? identify(element),
        let info = windowInfo(for: windowID)
      else { return }
      continuation.yield(.updated(info))
    }
  }

  private func identify(_ element: AXUIElement) -> WindowID? {
    elements.first { CFEqual($0.value, element) }?.key
  }

  private func windowInfo(for windowID: WindowID) -> WindowInfo? {
    guard let element = elements[windowID], let processID = owners[windowID],
      let frame = AXBridge.frame(of: element)
    else { return nil }
    let app = NSRunningApplication(processIdentifier: processID)
    return WindowInfo(
      id: windowID,
      processID: processID,
      appName: app?.localizedName ?? "pid \(processID)",
      bundleID: app?.bundleIdentifier,
      title: AXBridge.string(kAXTitleAttribute, of: element) ?? "",
      frame: frame,
      kind: WindowKind.classify(
        role: AXBridge.string(kAXRoleAttribute, of: element),
        subrole: AXBridge.string(kAXSubroleAttribute, of: element)
      ),
      isMinimized: AXBridge.bool(kAXMinimizedAttribute, of: element) ?? false,
      isFullscreen: AXBridge.bool("AXFullScreen", of: element) ?? false,
      isFocused: windowID == focusedID
    )
  }
}

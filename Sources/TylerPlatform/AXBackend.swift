import AppKit
import ApplicationServices
import TylerCore
import TylerRuntime
import TylerServer

/// The real `WindowSystem`, on the Accessibility API and `NSWorkspace`'s apps.
@MainActor
package final class AXBackend: WindowSystem {
  package let events: AsyncStream<WindowEvent>

  private static let log = TylerLog(category: "ax")
  private static let maxAttachAttempts = 6
  private static let retryDelay = Duration.milliseconds(500)

  private let continuation: AsyncStream<WindowEvent>.Continuation
  private var observers: [pid_t: AppObserver] = [:]
  private var retries: [pid_t: Task<Void, Never>] = [:]
  private var windows = TrackedWindows()
  private var focusedID: WindowID?
  private var pendingReads = PendingReads()
  private let steps = StepWriter()
  private var pendingReadsTask: Task<Void, Never>?
  private let runningApps = RunningAppsObserver()
  private var isStarted = false

  package init() {
    (events, continuation) = AsyncStream.makeStream(of: WindowEvent.self)
  }

  // MARK: - WindowSystem

  package func start() {
    guard !isStarted else { return }
    isStarted = true
    AXBridge.limitMessagingTimeout()
    runningApps.start(
      .init(
        launched: { [weak self] in self?.attach(processID: $0, attempt: 1) },
        activated: { [weak self] in self?.appActivated(processID: $0) },
        quit: { [weak self] in self?.detachQuitApps() }))
    for app in NSWorkspace.shared.runningApplications {
      attach(processID: app.processIdentifier, attempt: 1)
    }
  }

  package func stop() {
    guard isStarted else { return }
    isStarted = false
    runningApps.stop()
    for retry in retries.values { retry.cancel() }
    retries = [:]
    for observer in observers.values { observer.stop() }
    observers = [:]
    windows.forgetAll()
    focusedID = nil
    pendingReadsTask?.cancel()
    pendingReadsTask = nil
    _ = pendingReads.takeAll()
    steps.forgetAll()
  }

  package func snapshot() -> [WindowInfo] {
    windows.ids.compactMap { windowInfo(for: $0) }
  }

  package func focus(_ windowID: WindowID) throws(WindowSystemError) {
    guard let element = windows.element(of: windowID),
      let processID = windows.processID(of: windowID)
    else {
      throw .windowGone(windowID)
    }
    try steps.refuseIfUnresponsive(processID)
    try check(AXBridge.raise(window: element, in: processID), for: windowID)
  }

  package func close(_ windowID: WindowID) throws(WindowSystemError) {
    guard let element = windows.element(of: windowID) else { throw .windowGone(windowID) }
    try check(AXBridge.close(window: element), for: windowID)
  }

  /// Makes tylerd frontmost. It has no windows, so keys go nowhere until the user or a command
  /// focuses a window again.
  package func unfocus() throws(WindowSystemError) {
    let status = AXBridge.makeFrontmost(processID: ProcessInfo.processInfo.processIdentifier)
    guard status == .success else {
      throw Self.refusal(status)
    }
    setFocus(nil)
  }

  private func check(_ status: AXError, for windowID: WindowID) throws(WindowSystemError) {
    switch status {
    case .success:
      return
    case .invalidUIElement:
      // The window closed under us. Its destroyed notification may never come (registering for
      // it can fail right after an app launches), so forget it here: the manager then drops it
      // from its workspace instead of keeping an empty slot for it.
      forget(windowID)
      throw .windowGone(windowID)
    default:
      if status == .cannotComplete, let processID = windows.processID(of: windowID) {
        steps.noteTimeout(of: processID)
      }
      throw Self.refusal(status)
    }
  }

  /// Only the reason: the caller says what it asked for, of which window.
  static func refusal(_ status: AXError) -> WindowSystemError {
    status == .cannotComplete
      ? .refused("its app didn't answer") : .refused("AX error \(status.rawValue)")
  }

  // MARK: - Apps

  var attachedProcessIDs: [pid_t] { observers.keys.sorted() }

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
      // A freshly launched app may have come to the front before its first attempt succeeded.
      if NSWorkspace.shared.frontmostApplication?.processIdentifier == processID {
        readFocus(of: processID)
      }
    } catch {
      let name = app.localizedName ?? String(processID)
      Self.log.info(
        "app observing failed - \(name) (pid \(processID)) - attempt \(attempt): "
          + String(describing: error))
      scheduleRetry(processID: processID, attempt: attempt)
    }
  }

  /// A freshly launched app often refuses AX for a moment; try again shortly.
  private func scheduleRetry(processID: pid_t, attempt: Int) {
    guard attempt < Self.maxAttachAttempts else {
      let name = NSRunningApplication(processIdentifier: processID)?.localizedName ?? "?"
      Self.log.warning(
        "app observing stopped - \(name) (pid \(processID)) - gave up after \(attempt) attempts; "
          + "tries again when it comes to the front")
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

  private func detachQuitApps() {
    let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
    for processID in Set(observers.keys).union(retries.keys) where !running.contains(processID) {
      detach(processID: processID)
    }
  }

  private func detach(processID: pid_t) {
    retries[processID]?.cancel()
    retries[processID] = nil
    observers[processID]?.stop()
    observers[processID] = nil
    steps.forget(processID)
    let windowIDs = windows.ids(ownedBy: processID)
    Self.log.info("app quit - pid \(processID) - dropping \(windowIDs.count) windows")
    for windowID in windowIDs { forget(windowID) }
  }

  private func appActivated(processID: pid_t) {
    // An app that ran out of attach attempts (a slow launch, or busy when tylerd started) or
    // became a regular app after launching gets another chance whenever it comes to the front.
    if observers[processID] == nil, retries[processID] == nil {
      attach(processID: processID, attempt: 1)
    } else if observers[processID] != nil {
      readFocus(of: processID)
    }
  }

  private func readFocus(of processID: pid_t) {
    let application = AXBridge.applicationElement(processID: processID)
    let windowID = AXBridge.focusedWindow(of: application).flatMap { window in
      register(window: window, processID: processID)
    }
    setFocus(windowID)
  }

  // MARK: - Windows

  /// Starts tracking `window` if it's new. Returns its id, or `nil` if it has none.
  @discardableResult
  private func register(window: AXUIElement, processID: pid_t) -> WindowID? {
    guard let windowID = AXBridge.windowID(of: window) else {
      Self.log.info("window tracking skipped - pid \(processID) - it has no window number")
      return nil
    }
    guard !windows.contains(windowID) else { return windowID }
    guard let observer = observers[processID] else {
      Self.log.debug("window tracking skipped - \(named(windowID)) - its app isn't observed")
      return nil
    }

    windows.track(window, as: windowID, ownedBy: processID)
    let failures = observer.observe(window: window)
    if let info = windowInfo(for: windowID) {
      continuation.yield(.created(info))
    }
    // After the first read, so the line names the window.
    for failure in failures {
      Self.log.warning(
        "window observing failed - \(named(windowID)) - won't update live: "
          + String(describing: failure))
    }
    return windowID
  }

  private func forget(_ windowID: WindowID) {
    guard windows.forget(windowID) else { return }
    pendingReads.forget(windowID)
    if focusedID == windowID { focusedID = nil }
    continuation.yield(.destroyed(windowID))
  }

  private func setFocus(_ windowID: WindowID?) {
    guard focusedID != windowID else { return }
    focusedID = windowID
    continuation.yield(.focused(windowID))
  }

  private func named(_ windowID: WindowID) -> String {
    WindowInfo.logName(windowID, windows.lastRead(of: windowID))
  }

  private func windowInfo(for windowID: WindowID) -> WindowInfo? {
    windows.read(windowID, isFocused: windowID == focusedID)
  }
}

/// Moving and resizing windows; here because it reads and updates the window system's private state.
extension AXBackend {
  package func setFrame(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    let element = try settledElement(windowID)
    // A window that already has the size only needs moving: one write instead of three. Should
    // the size turn out to differ after all (the last read is out of date), the full move
    // follows.
    var current = windows.lastRead(of: windowID)?.frame
    var actual: CGRect?
    if current?.size == frame.size {
      try check(AXBridge.setPosition(frame.origin, of: element), for: windowID)
      actual = AXBridge.frame(of: element)
      current = actual
    }
    if actual?.size != frame.size {
      if let current, let origin = frame.clearingOrigin(from: current) {
        Self.log.debug(
          "window moved before resizing - \(named(windowID)) - it reached past its frame")
        try check(AXBridge.setPosition(origin, of: element), for: windowID)
      }
      try check(AXBridge.setFrame(frame, of: element), for: windowID)
      actual = AXBridge.frame(of: element)
    }
    // The app may have clamped the size; tell the manager what it really is.
    guard let actual, let info = noteFrame(actual, of: windowID) else { return }
    continuation.yield(.updated(info))
  }

  private func noteFrame(
    _ frame: CGRect, isFullscreen: Bool? = nil, of windowID: WindowID
  ) -> WindowInfo? {
    windows.note(frame, isFullscreen: isFullscreen, of: windowID, isFocused: windowID == focusedID)
  }

  package func setPosition(_ origin: CGPoint, of windowID: WindowID) throws(WindowSystemError) {
    guard let element = windows.element(of: windowID),
      let processID = windows.processID(of: windowID)
    else { throw .windowGone(windowID) }
    try steps.move(windowID, element, by: [.position(origin)], in: processID)
  }

  /// Ordered from the frame last read, which lags behind the steps but grows or shrinks the same
  /// way along a straight track.
  package func setFrameStep(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    guard let element = windows.element(of: windowID),
      let processID = windows.processID(of: windowID)
    else { throw .windowGone(windowID) }
    let writes =
      windows.lastRead(of: windowID).flatMap { FrameWrite.inPassing(from: $0.frame, to: frame) }
      ?? [.position(frame.origin), .size(frame.size)]
    try steps.move(windowID, element, by: writes, in: processID)
  }

  package func takeQueuedWrites() -> MotionCost.Queued { steps.takeStatistics() }

  /// The window's element, once the moves still queued for it are written.
  private func settledElement(_ windowID: WindowID) throws(WindowSystemError) -> AXUIElement {
    guard let element = windows.element(of: windowID) else { throw .windowGone(windowID) }
    if let processID = windows.processID(of: windowID) {
      try steps.settle(windowID, in: processID)
    }
    return element
  }

  package func setFrameInPassing(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    let element = try settledElement(windowID)
    guard let current = windows.lastRead(of: windowID)?.frame,
      let writes = FrameWrite.inPassing(from: current, to: frame)
    else { return try setFrame(frame, of: windowID) }
    for write in writes {
      try check(AXBridge.write(write, to: element), for: windowID)
    }
  }
}

/// What an app's notifications change. In this file because it reads the window system's private state.
extension AXBackend {
  private func handle(_ notification: String, element: AXUIElement, processID: pid_t) {
    switch notification {
    case kAXWindowCreatedNotification:
      register(window: element, processID: processID)
    case kAXFocusedWindowChangedNotification:
      setFocus(register(window: element, processID: processID))
    case kAXUIElementDestroyedNotification:
      // The element is already invalid, so it can't be asked for its id; find it by identity.
      if let windowID = windows.identify(element) {
        forget(windowID)
      }
    default:
      guard let windowID = AXBridge.windowID(of: element) ?? windows.identify(element) else {
        Self.log.info(
          "notification dropped - pid \(processID) - \(notification) of an unknown window")
        return
      }
      if pendingReads.note(notification, for: windowID) {
        // Read once the burst is over: after the notifications already waiting.
        pendingReadsTask = pendingReadsTask ?? Task { [weak self] in self?.readPending() }
        return
      }
      // Minimized or deminimized: a missed one leaves a window tiled, so it is read at once and
      // a failure is worth seeing by default.
      guard let info = windowInfo(for: windowID) else {
        Self.log.warning(
          "notification dropped - \(named(windowID)) - \(notification): the read failed")
        return
      }
      continuation.yield(.updated(info))
    }
  }

  private func readPending() {
    pendingReadsTask = nil
    for (windowID, depth) in pendingReads.takeAll() {
      guard let element = windows.element(of: windowID) else { continue }
      let info: WindowInfo? =
        switch depth {
        case .frame: AXBridge.frame(of: element).flatMap { noteFrame($0, of: windowID) }
        case .frameAndFullscreen:
          AXBridge.frameAndFullscreen(of: element).flatMap {
            noteFrame($0.0, isFullscreen: $0.1, of: windowID)
          }
        case .full: windowInfo(for: windowID)
        }
      guard let info else {
        Self.log.info("window update dropped - \(named(windowID)) - the read failed")
        continue
      }
      continuation.yield(.updated(info))
    }
  }
}

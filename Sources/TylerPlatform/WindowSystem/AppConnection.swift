import ApplicationServices
import TylerCore
import TylerRuntime
import TylerServer

/// tylerd's connection to one app: its windows, reading them, its notifications turned into
/// reports, moving, focusing and closing its windows, and whether it answers. It knows nothing of
/// other apps, so not which window has the focus across them: the
/// window system, which it reports to, does.
@MainActor
final class AppConnection {
  enum Report {
    case created(WindowInfo)
    case updated(WindowInfo)
    case destroyed(WindowID)
    /// The app's focused window is now this one.
    case focused(WindowID?)
  }

  /// A window and the writes that take it where it goes. An `AXUIElement` is an immutable handle
  /// on an element of another process, and the Accessibility API may be called from any thread.
  struct Move: @unchecked Sendable {
    let element: AXUIElement
    let writes: [FrameWrite]
  }

  nonisolated private static let log = TylerLog(category: "ax")

  let processID: pid_t
  private let application: AXUIElement
  private let bridge: AXBridge
  private let reader: WindowReader
  private let report: (Report) -> Void
  private var windows = TrackedWindows()
  private var pendingReads = PendingReads()
  private var pendingReadsTask: Task<Void, Never>?
  /// Steps are written on a queue of the app's own, so the windows of a frame move side by side,
  /// a slow app skips frames instead of holding up the others, and the main thread stays free.
  private let steps: AppWriteQueue<WindowID, Move>
  private var pause: AppPause

  init(
    processID: pid_t, bridge: AXBridge, reader: WindowReader, clock: any Clock<Duration>,
    report: @escaping (Report) -> Void
  ) {
    self.processID = processID
    application = bridge.applicationElement(processID: processID)
    self.bridge = bridge
    self.reader = reader
    pause = AppPause(clock: clock)
    self.report = report
    steps = AppWriteQueue(label: "tyler.moves.\(processID)") { windowID, move in
      Self.write(move, of: windowID, through: bridge)
    }
  }

  /// Observes the app and reports its windows. Throws if the app refuses, which is common for an
  /// app that has only just launched.
  func open() throws(AXBridge.ObservingFailure) {
    try bridge.observe(application, processID: processID) { [weak self] notification, element in
      self?.handle(notification, element: element)
    }
    for window in bridge.windows(of: application) {
      register(window: window)
    }
  }

  /// Stops observing the app and forgets its windows without reporting them.
  func close() {
    bridge.stopObserving(processID: processID)
    pendingReadsTask?.cancel()
    pendingReadsTask = nil
    _ = pendingReads.takeAll()
    windows.forgetAll()
  }

  var windowIDs: [WindowID] { windows.ids }

  /// Reads the window in full. Whether it has the focus is for the window system to say.
  func read(_ windowID: WindowID) -> WindowInfo? {
    windows.read(windowID, by: reader)
  }

  /// The last read with a new frame.
  private func note(_ frame: CGRect, isFullscreen: Bool? = nil, of id: WindowID) -> WindowInfo? {
    windows.note(frame, isFullscreen: isFullscreen, of: id)
  }

  /// Reports the window the app has focused.
  func readFocus() {
    report(.focused(bridge.focusedWindow(of: application).flatMap { register(window: $0) }))
  }

  /// Forgets a window that is gone, and reports it.
  func forget(_ windowID: WindowID) {
    guard windows.forget(windowID) else { return }
    pendingReads.forget(windowID)
    report(.destroyed(windowID))
  }

  /// The app's windows that aren't tracked, read again.
  func untrackedWindows() -> [WindowInfo] {
    bridge.windows(of: application).compactMap { element in
      guard let windowID = bridge.windowID(of: element), !windows.contains(windowID) else {
        return nil
      }
      return reader.read(
        element, id: windowID, processID: processID, known: nil)
    }
  }

  private func named(_ windowID: WindowID) -> String {
    WindowInfo.logName(windowID, windows.lastRead(of: windowID))
  }

  /// Starts tracking `window` if it's new. Returns its id, or `nil` if it has none.
  @discardableResult
  private func register(window: AXUIElement) -> WindowID? {
    guard let windowID = bridge.windowID(of: window) else {
      Self.log.info("window tracking skipped - pid \(processID) - it has no window number")
      return nil
    }
    guard !windows.contains(windowID) else { return windowID }

    windows.track(window, as: windowID, ownedBy: processID)
    let failures = bridge.observe(window: window, processID: processID)
    if let info = read(windowID) {
      report(.created(info))
    }
    // After the first read, so the line names the window.
    for failure in failures {
      Self.log.warning(
        "window observing failed - \(named(windowID)) - won't update live: "
          + String(describing: failure))
    }
    return windowID
  }

  private func handle(_ notification: String, element: AXUIElement) {
    switch notification {
    case kAXWindowCreatedNotification:
      register(window: element)
    case kAXFocusedWindowChangedNotification:
      report(.focused(register(window: element)))
    case kAXUIElementDestroyedNotification:
      // The element is already invalid, so it can't be asked for its id; find it by identity.
      if let windowID = windows.identify(element) {
        forget(windowID)
      }
    default:
      guard let windowID = bridge.windowID(of: element) ?? windows.identify(element) else {
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
      guard let info = read(windowID) else {
        Self.log.warning(
          "notification dropped - \(named(windowID)) - \(notification): the read failed")
        return
      }
      report(.updated(info))
    }
  }

  private func readPending() {
    pendingReadsTask = nil
    for (windowID, depth) in pendingReads.takeAll() {
      guard let element = windows.element(of: windowID) else { continue }
      let info: WindowInfo? =
        switch depth {
        case .frame: bridge.frame(of: element).flatMap { note($0, of: windowID) }
        case .frameAndFullscreen:
          bridge.frameAndFullscreen(of: element).flatMap {
            note($0.0, isFullscreen: $0.1, of: windowID)
          }
        case .full: read(windowID)
        }
      guard let info else {
        Self.log.info("window update dropped - \(named(windowID)) - the read failed")
        continue
      }
      report(.updated(info))
    }
  }
}

/// Moving, focusing and closing; here because it reads and updates the connection's private state.
extension AppConnection {
  func setFrame(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    let element = try settledElement(windowID)
    // A window that already has the size only needs moving: one write instead of three. Should
    // the size turn out to differ after all (the last read is out of date), the full move
    // follows.
    var current = windows.lastRead(of: windowID)?.frame
    var actual: CGRect?
    if current?.size == frame.size {
      try check(bridge.setPosition(frame.origin, of: element), for: windowID)
      actual = bridge.frame(of: element)
      current = actual
    }
    if actual?.size != frame.size {
      if let current, let origin = frame.clearingOrigin(from: current) {
        Self.log.debug(
          "window moved before resizing - \(named(windowID)) - it reached past its frame")
        try check(bridge.setPosition(origin, of: element), for: windowID)
      }
      try check(bridge.setFrame(frame, of: element), for: windowID)
      actual = bridge.frame(of: element)
    }
    // The app may have clamped the size; tell the manager what it really is.
    guard let actual, let info = note(actual, of: windowID) else { return }
    report(.updated(info))
  }

  func setPosition(_ origin: CGPoint, of windowID: WindowID) throws(WindowSystemError) {
    try move(windowID, by: [.position(origin)])
  }

  /// Ordered from the frame last read, which lags behind the steps but grows or shrinks the same
  /// way along a straight track.
  func setFrameStep(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    let writes =
      windows.lastRead(of: windowID).flatMap { FrameWrite.inPassing(from: $0.frame, to: frame) }
      ?? [.position(frame.origin), .size(frame.size)]
    try move(windowID, by: writes)
  }

  func setFrameInPassing(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    let element = try settledElement(windowID)
    guard let current = windows.lastRead(of: windowID)?.frame,
      let writes = FrameWrite.inPassing(from: current, to: frame)
    else { return try setFrame(frame, of: windowID) }
    for write in writes {
      try check(bridge.write(write, to: element), for: windowID)
    }
  }

  /// What the step queue wrote since the last call.
  func takeQueuedWrites() -> AppWriteQueue<WindowID, Move>.Statistics { steps.takeStatistics() }

  func focus(_ windowID: WindowID) throws(WindowSystemError) {
    let element = try element(of: windowID)
    try pause.refuseIfOn()
    try check(bridge.raise(window: element, in: processID), for: windowID)
  }

  func close(_ windowID: WindowID) throws(WindowSystemError) {
    try check(bridge.close(window: try element(of: windowID)), for: windowID)
  }

  private func element(of windowID: WindowID) throws(WindowSystemError) -> AXUIElement {
    guard let element = windows.element(of: windowID) else { throw .windowGone(windowID) }
    return element
  }

  private func move(_ windowID: WindowID, by writes: [FrameWrite]) throws(WindowSystemError) {
    let element = try element(of: windowID)
    try pause.refuseIfOn()
    steps.submit(Move(element: element, writes: writes), for: windowID)
  }

  /// The window's element, once the steps still queued are written: the step waiting for it is
  /// dropped, and a write on the main thread then lands after every step already sent.
  private func settledElement(_ windowID: WindowID) throws(WindowSystemError) -> AXUIElement {
    let element = try element(of: windowID)
    try pause.refuseIfOn()
    steps.discard(windowID)
    steps.waitUntilWritten()
    return element
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
      if status == .cannotComplete { noteTimeout() }
      throw WindowSystemError(refusal: status)
    }
  }

  // MARK: - Whether the app answers

  /// Skips the app for a while, from now: a call to it timed out.
  private func noteTimeout() {
    guard pause.start() else { return }
    Self.log.warning(
      "app skipping started - pid \(processID) - it didn't answer within "
        + "\(AXBridge.messagingTimeout) s; its windows aren't moved for \(AppPause.length)")
  }

  nonisolated private static func write(
    _ move: Move, of windowID: WindowID, through bridge: AXBridge
  ) {
    for write in move.writes {
      let status = bridge.write(write, to: move.element)
      if status != .success {
        // One missed frame is invisible; the final placement reports real failures.
        log.debug("window stepping failed - #\(windowID) - AX error \(status.rawValue)")
        return
      }
    }
  }
}

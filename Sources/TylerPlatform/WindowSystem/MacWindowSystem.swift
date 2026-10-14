import AppKit
import ApplicationServices
import TylerCore
import TylerRuntime
import TylerServer

/// The real `WindowSystem`, on the Accessibility API (`AXClient`) and `NSWorkspace`'s apps
/// (`WorkspaceClient`).
@MainActor
package final class MacWindowSystem: WindowSystem {
  package let events: AsyncStream<WindowEvent>

  private static let log = TylerLog(category: "ax")
  private static let maxAttachAttempts = 6
  private static let retryDelay = Duration.milliseconds(500)

  private let continuation: AsyncStream<WindowEvent>.Continuation
  let bridge: AXBridge
  let workspace: any WorkspaceClient
  let reader: WindowReader
  private let clock: any Clock<Duration>
  private var connections: [pid_t: AppConnection] = [:]
  private var retries: [pid_t: Task<Void, Never>] = [:]
  /// Which app each window is in, changed only by the connections' reports.
  private var owners: [WindowID: pid_t] = [:]
  private var focusedID: WindowID?
  private let steps: StepWriter
  private var isStarted = false

  package convenience init() {
    self.init(client: MacAXClient(), workspace: MacWorkspaceClient(), clock: ContinuousClock())
  }

  init(client: any AXClient, workspace: any WorkspaceClient, clock: any Clock<Duration>) {
    (events, continuation) = AsyncStream.makeStream(of: WindowEvent.self)
    bridge = AXBridge(client: client)
    self.workspace = workspace
    reader = WindowReader(bridge: bridge, workspace: workspace)
    self.clock = clock
    steps = StepWriter(write: StepWriter.writing(through: bridge))
  }

  // MARK: - WindowSystem

  package func start() {
    guard !isStarted else { return }
    isStarted = true
    bridge.limitMessagingTimeout()
    workspace.start(
      launched: { [weak self] in self?.attach(processID: $0, attempt: 1) },
      activated: { [weak self] in self?.appActivated(processID: $0) },
      quit: { [weak self] in self?.detachQuitApps() })
    for app in workspace.runningApps {
      attach(processID: app.processID, attempt: 1)
    }
  }

  package func stop() {
    guard isStarted else { return }
    isStarted = false
    workspace.stop()
    for retry in retries.values { retry.cancel() }
    retries = [:]
    for connection in connections.values { connection.close() }
    connections = [:]
    owners = [:]
    focusedID = nil
    steps.forgetAll()
  }

  package func snapshot() -> [WindowInfo] {
    owners.keys.sorted().compactMap { windowInfo(for: $0) }
  }

  package func focus(_ windowID: WindowID) throws(WindowSystemError) {
    let (connection, element) = try located(windowID)
    try steps.refuseIfUnresponsive(connection.processID)
    try check(bridge.raise(window: element, in: connection.processID), for: windowID)
  }

  package func close(_ windowID: WindowID) throws(WindowSystemError) {
    let (_, element) = try located(windowID)
    try check(bridge.close(window: element), for: windowID)
  }

  /// Makes tylerd frontmost. It has no windows, so keys go nowhere until the user or a command
  /// focuses a window again.
  package func unfocus() throws(WindowSystemError) {
    let status = bridge.makeFrontmost(processID: workspace.ownProcessID)
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
      connection(of: windowID)?.forget(windowID)
      throw .windowGone(windowID)
    default:
      if status == .cannotComplete, let processID = owners[windowID] {
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

  var attachedApps: [AppConnection] {
    connections.keys.sorted().compactMap { connections[$0] }
  }

  private func attach(processID: pid_t, attempt: Int) {
    guard isStarted, connections[processID] == nil,
      processID != workspace.ownProcessID,
      let app = workspace.runningApp(processID),
      app.activationPolicy == .regular
    else { return }

    let connection = AppConnection(processID: processID, bridge: bridge, reader: reader) {
      [weak self] report in self?.receive(report, from: processID)
    }
    do {
      try connection.open()
      connections[processID] = connection
      retries[processID] = nil
      // A freshly launched app may have come to the front before its first attempt succeeded.
      if workspace.frontmostProcessID == processID {
        connection.readFocus()
      }
    } catch {
      let name = app.name ?? String(processID)
      Self.log.info(
        "app observing failed - \(name) (pid \(processID)) - attempt \(attempt): "
          + String(describing: error))
      scheduleRetry(processID: processID, attempt: attempt)
    }
  }

  /// A freshly launched app often refuses AX for a moment; try again shortly.
  private func scheduleRetry(processID: pid_t, attempt: Int) {
    guard attempt < Self.maxAttachAttempts else {
      let name = workspace.runningApp(processID)?.name ?? "?"
      Self.log.warning(
        "app observing stopped - \(name) (pid \(processID)) - gave up after \(attempt) attempts; "
          + "tries again when it comes to the front")
      retries[processID] = nil
      return
    }
    retries[processID]?.cancel()
    let clock = clock  // Swift opens the existential from a local, not from the stored property.
    retries[processID] = Task { [weak self] in
      do {
        try await clock.sleep(for: Self.retryDelay)
      } catch {
        return  // Cancelled by stop() or a newer retry; nothing left to do.
      }
      self?.attach(processID: processID, attempt: attempt + 1)
    }
  }

  private func detachQuitApps() {
    let running = Set(workspace.runningApps.map(\.processID))
    for processID in Set(connections.keys).union(retries.keys) where !running.contains(processID) {
      detach(processID: processID)
    }
  }

  private func detach(processID: pid_t) {
    retries[processID]?.cancel()
    retries[processID] = nil
    steps.forget(processID)
    guard let connection = connections.removeValue(forKey: processID) else { return }
    let windowIDs = connection.windowIDs
    Self.log.info("app quit - pid \(processID) - dropping \(windowIDs.count) windows")
    for windowID in windowIDs { connection.forget(windowID) }
    connection.close()
  }

  private func appActivated(processID: pid_t) {
    // An app that ran out of attach attempts (a slow launch, or busy when tylerd started) or
    // became a regular app after launching gets another chance whenever it comes to the front.
    if let connection = connections[processID] {
      connection.readFocus()
    } else if retries[processID] == nil {
      attach(processID: processID, attempt: 1)
    }
  }

  // MARK: - Windows

  private func receive(_ report: AppConnection.Report, from processID: pid_t) {
    switch report {
    case .created(let info):
      owners[info.id] = processID
      continuation.yield(.created(focusing(info)))
    case .updated(let info):
      continuation.yield(.updated(focusing(info)))
    case .destroyed(let windowID):
      owners[windowID] = nil
      if focusedID == windowID { focusedID = nil }
      continuation.yield(.destroyed(windowID))
    case .focused(let windowID):
      setFocus(windowID)
    }
  }

  private func setFocus(_ windowID: WindowID?) {
    guard focusedID != windowID else { return }
    focusedID = windowID
    continuation.yield(.focused(windowID))
  }

  private func focusing(_ info: WindowInfo) -> WindowInfo {
    var info = info
    info.isFocused = info.id == focusedID
    return info
  }

  private func connection(of windowID: WindowID) -> AppConnection? {
    owners[windowID].flatMap { connections[$0] }
  }

  /// The window's connection and element, or `windowGone`.
  private func located(_ id: WindowID) throws(WindowSystemError) -> (AppConnection, AXUIElement) {
    guard let connection = connection(of: id), let element = connection.element(of: id) else {
      throw .windowGone(id)
    }
    return (connection, element)
  }

  private func named(_ windowID: WindowID) -> String {
    connection(of: windowID)?.named(windowID) ?? WindowInfo.logName(windowID, nil)
  }

  private func windowInfo(for windowID: WindowID) -> WindowInfo? {
    connection(of: windowID)?.read(windowID).map(focusing)
  }
}

/// Moving and resizing windows; here because it reads and updates the window system's private state.
extension MacWindowSystem {
  package func setFrame(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    let element = try settledElement(windowID)
    // A window that already has the size only needs moving: one write instead of three. Should
    // the size turn out to differ after all (the last read is out of date), the full move
    // follows.
    var current = connection(of: windowID)?.lastRead(of: windowID)?.frame
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
    guard let actual, let info = connection(of: windowID)?.note(actual, of: windowID) else {
      return
    }
    continuation.yield(.updated(focusing(info)))
  }

  package func setPosition(_ origin: CGPoint, of windowID: WindowID) throws(WindowSystemError) {
    let (connection, element) = try located(windowID)
    try steps.move(windowID, element, by: [.position(origin)], in: connection.processID)
  }

  /// Ordered from the frame last read, which lags behind the steps but grows or shrinks the same
  /// way along a straight track.
  package func setFrameStep(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    let (connection, element) = try located(windowID)
    let writes =
      connection.lastRead(of: windowID).flatMap { FrameWrite.inPassing(from: $0.frame, to: frame) }
      ?? [.position(frame.origin), .size(frame.size)]
    try steps.move(windowID, element, by: writes, in: connection.processID)
  }

  package func takeQueuedWrites() -> MotionCost.Queued { steps.takeStatistics() }

  /// The window's element, once the moves still queued for it are written.
  private func settledElement(_ windowID: WindowID) throws(WindowSystemError) -> AXUIElement {
    let (connection, element) = try located(windowID)
    try steps.settle(windowID, in: connection.processID)
    return element
  }

  package func setFrameInPassing(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    let element = try settledElement(windowID)
    guard let current = connection(of: windowID)?.lastRead(of: windowID)?.frame,
      let writes = FrameWrite.inPassing(from: current, to: frame)
    else { return try setFrame(frame, of: windowID) }
    for write in writes {
      try check(bridge.write(write, to: element), for: windowID)
    }
  }
}

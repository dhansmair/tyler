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
  private let screenLock: any ScreenLock
  private var connections: [pid_t: AppConnection] = [:]
  private var retries: [pid_t: Task<Void, Never>] = [:]
  /// Which app each window is in, changed only by the connections' reports.
  private var owners: [WindowID: pid_t] = [:]
  private var focusedID: WindowID?
  private var isStarted = false

  package convenience init(screenLock: any ScreenLock) {
    self.init(
      client: MacAXClient(), workspace: MacWorkspaceClient(), clock: ContinuousClock(),
      screenLock: screenLock)
  }

  init(
    client: any AXClient, workspace: any WorkspaceClient, clock: any Clock<Duration>,
    screenLock: any ScreenLock
  ) {
    (events, continuation) = AsyncStream.makeStream(of: WindowEvent.self)
    bridge = AXBridge(client: client)
    self.workspace = workspace
    reader = WindowReader(bridge: bridge, workspace: workspace)
    self.clock = clock
    self.screenLock = screenLock
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
  }

  package var isAttaching: Bool { !retries.isEmpty }

  package func snapshot() -> [WindowInfo] {
    owners.keys.sorted().compactMap { windowInfo(for: $0) }
  }

  package func focus(_ windowID: WindowID) throws(WindowSystemError) {
    try owner(of: windowID).focus(windowID)
  }

  package func close(_ windowID: WindowID) throws(WindowSystemError) {
    try owner(of: windowID).close(windowID)
  }

  /// Makes tylerd frontmost. It has no windows, so keys go nowhere until the user or a command
  /// focuses a window again.
  package func unfocus() throws(WindowSystemError) {
    let status = bridge.makeFrontmost(processID: workspace.ownProcessID)
    guard status == .success else {
      throw WindowSystemError(refusal: status)
    }
    setFocus(nil)
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

    let shared = AppConnection.Shared(
      bridge: bridge, reader: reader, clock: clock, screenLock: screenLock)
    let connection = AppConnection(processID: processID, shared: shared) { [weak self] report in
      self?.receive(report, from: processID)
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
    guard let connection = connections.removeValue(forKey: processID) else { return }
    let windowIDs = connection.windowIDs
    Self.log.info("app quit - pid \(processID) - dropping \(windowIDs.count) windows")
    for windowID in windowIDs { connection.forget(windowID, because: .appQuit) }
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

  private func owner(of windowID: WindowID) throws(WindowSystemError) -> AppConnection {
    guard let connection = connection(of: windowID) else {
      Self.log.info("window call failed - \(WindowInfo.logName(windowID, nil)) - no app owns it")
      throw .windowGone(windowID)
    }
    return connection
  }

  private func windowInfo(for windowID: WindowID) -> WindowInfo? {
    connection(of: windowID)?.read(windowID).map(focusing)
  }
}

extension MacWindowSystem {
  @discardableResult
  package func setFrame(
    _ frame: CGRect, of windowID: WindowID
  ) throws(WindowSystemError) -> CGRect? {
    try owner(of: windowID).setFrame(frame, of: windowID)
  }

  package func setPosition(_ origin: CGPoint, of windowID: WindowID) throws(WindowSystemError) {
    try owner(of: windowID).setPosition(origin, of: windowID)
  }

  package func setFrameStep(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    try owner(of: windowID).setFrameStep(frame, of: windowID)
  }

  package func setFrameInPassing(_ frame: CGRect, of windowID: WindowID) throws(WindowSystemError) {
    try owner(of: windowID).setFrameInPassing(frame, of: windowID)
  }

  /// What the apps' step queues wrote since the last call, all apps together.
  package func takeQueuedWrites() -> MotionCost.Queued {
    attachedApps.reduce(into: MotionCost.Queued()) { total, connection in
      let statistics = connection.takeQueuedWrites()
      total.add(
        written: statistics.written, skipped: statistics.skipped, time: statistics.time,
        slowest: statistics.slowest.map {
          MotionCost.Write(windowID: $0.key, duration: $0.duration)
        })
    }
  }
}

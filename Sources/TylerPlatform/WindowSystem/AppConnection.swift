import ApplicationServices
import TylerCore
import TylerRuntime

/// tylerd's connection to one app: its windows, reading them, and its notifications turned into
/// reports. It knows nothing of other apps, so not which window has the focus across them: the
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

  private static let log = TylerLog(category: "ax")

  let processID: pid_t
  private let application: AXUIElement
  private let bridge: AXBridge
  private let reader: WindowReader
  private let report: (Report) -> Void
  private var windows = TrackedWindows()
  private var pendingReads = PendingReads()
  private var pendingReadsTask: Task<Void, Never>?

  init(
    processID: pid_t, bridge: AXBridge, reader: WindowReader,
    report: @escaping (Report) -> Void
  ) {
    self.processID = processID
    application = bridge.applicationElement(processID: processID)
    self.bridge = bridge
    self.reader = reader
    self.report = report
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

  func element(of windowID: WindowID) -> AXUIElement? { windows.element(of: windowID) }
  func lastRead(of windowID: WindowID) -> WindowInfo? { windows.lastRead(of: windowID) }

  /// Reads the window in full. Its `isFocused` is for the window system to set.
  func read(_ windowID: WindowID) -> WindowInfo? {
    windows.read(windowID, isFocused: false, by: reader)
  }

  /// The last read with a new frame. Its `isFocused` is for the window system to set.
  func note(_ frame: CGRect, isFullscreen: Bool? = nil, of windowID: WindowID) -> WindowInfo? {
    windows.note(frame, isFullscreen: isFullscreen, of: windowID, isFocused: false)
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
        element, id: windowID, processID: processID, known: nil, isFocused: false)
    }
  }

  func named(_ windowID: WindowID) -> String {
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

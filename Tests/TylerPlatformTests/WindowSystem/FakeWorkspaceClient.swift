import AppKit

@testable import TylerPlatform

/// Apps launching, coming to the front and quitting.
@MainActor
final class FakeWorkspaceClient: WorkspaceClient {
  private(set) var runningApps: [RunningApp] = []
  var frontmostProcessID: pid_t?
  let ownProcessID: pid_t = 1
  private var onLaunch: (@MainActor (pid_t) -> Void)?
  private var onActivate: (@MainActor (pid_t) -> Void)?
  private var onQuit: (@MainActor () -> Void)?

  /// Running before the window system starts: no launch is reported.
  func add(_ processID: pid_t, name: String, policy: NSApplication.ActivationPolicy = .regular) {
    runningApps.append(
      RunningApp(
        processID: processID, activationPolicy: policy, name: name, bundleID: "test.\(name)"))
  }

  func launch(_ processID: pid_t, name: String) {
    add(processID, name: name)
    onLaunch?(processID)
  }

  func activate(_ processID: pid_t) {
    frontmostProcessID = processID
    onActivate?(processID)
  }

  func quit(_ processID: pid_t) {
    runningApps.removeAll { $0.processID == processID }
    onQuit?()
  }

  func runningApp(_ processID: pid_t) -> RunningApp? {
    runningApps.first { $0.processID == processID }
  }

  func start(
    launched: @escaping @MainActor @Sendable (pid_t) -> Void,
    activated: @escaping @MainActor @Sendable (pid_t) -> Void,
    quit: @escaping @MainActor @Sendable () -> Void
  ) {
    onLaunch = launched
    onActivate = activated
    onQuit = quit
  }

  func stop() {
    onLaunch = nil
    onActivate = nil
    onQuit = nil
  }
}

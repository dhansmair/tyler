import AppKit

/// The real `WorkspaceClient`.
@MainActor
final class MacWorkspaceClient: WorkspaceClient {
  private var tokens: [any NSObjectProtocol] = []
  private var quitObservation: NSKeyValueObservation?

  nonisolated init() {}

  var runningApps: [RunningApp] { NSWorkspace.shared.runningApplications.map(Self.describe) }

  var frontmostProcessID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

  var ownProcessID: pid_t { ProcessInfo.processInfo.processIdentifier }

  func runningApp(_ processID: pid_t) -> RunningApp? {
    NSRunningApplication(processIdentifier: processID).map(Self.describe)
  }

  func start(
    launched: @escaping @MainActor @Sendable (pid_t) -> Void,
    activated: @escaping @MainActor @Sendable (pid_t) -> Void,
    quit: @escaping @MainActor @Sendable () -> Void
  ) {
    let center = NSWorkspace.shared.notificationCenter
    let names: [(Notification.Name, @MainActor @Sendable (pid_t) -> Void)] = [
      (NSWorkspace.didLaunchApplicationNotification, launched),
      (NSWorkspace.didActivateApplicationNotification, activated),
    ]
    for (name, action) in names {
      let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard let processID = app?.processIdentifier else { return }
        MainActor.assumeIsolated { action(processID) }
      }
      tokens.append(token)
    }
    // Not `didTerminateApplicationNotification`: an app that quits by itself when its last
    // window closes (Find My) never posts it, but does leave `runningApplications`.
    // The apps removed say -1 for their process id by then, so what is still running decides.
    quitObservation = NSWorkspace.shared.observe(\.runningApplications) { _, change in
      guard change.kind == .removal else { return }
      MainActor.assumeIsolated { quit() }
    }
  }

  func stop() {
    let center = NSWorkspace.shared.notificationCenter
    for token in tokens { center.removeObserver(token) }
    tokens = []
    quitObservation?.invalidate()
    quitObservation = nil
  }

  private static func describe(_ app: NSRunningApplication) -> RunningApp {
    RunningApp(
      processID: app.processIdentifier, activationPolicy: app.activationPolicy,
      name: app.localizedName, bundleID: app.bundleIdentifier)
  }
}

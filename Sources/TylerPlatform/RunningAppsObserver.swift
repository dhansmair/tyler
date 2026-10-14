import AppKit

/// Tells the backend when an app launches, comes to the front or quits.
@MainActor
final class RunningAppsObserver {
  struct Handlers {
    let launched: @MainActor @Sendable (pid_t) -> Void
    let activated: @MainActor @Sendable (pid_t) -> Void
    let quit: @MainActor @Sendable () -> Void
  }

  private var tokens: [any NSObjectProtocol] = []
  private var quitObservation: NSKeyValueObservation?

  func start(_ handlers: Handlers) {
    let center = NSWorkspace.shared.notificationCenter
    let names: [(Notification.Name, @MainActor @Sendable (pid_t) -> Void)] = [
      (NSWorkspace.didLaunchApplicationNotification, handlers.launched),
      (NSWorkspace.didActivateApplicationNotification, handlers.activated),
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
      MainActor.assumeIsolated { handlers.quit() }
    }
  }

  func stop() {
    let center = NSWorkspace.shared.notificationCenter
    for token in tokens { center.removeObserver(token) }
    tokens = []
    quitObservation?.invalidate()
    quitObservation = nil
  }
}

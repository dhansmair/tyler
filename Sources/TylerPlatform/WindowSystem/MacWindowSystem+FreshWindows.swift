import AppKit
import ApplicationServices
import TylerCore
import TylerServer

/// Reading every window again, for `tyler debug windows`.
extension MacWindowSystem {
  package func freshWindows() -> FreshWindows {
    let tracked = snapshot()
    let untracked = attachedApps.flatMap { $0.untrackedWindows() }
    let ownID = workspace.ownProcessID
    let attached = Set(attachedApps.map(\.processID))
    let unattached = workspace.runningApps.filter { app in
      app.activationPolicy == .regular && app.processID != ownID
        && !attached.contains(app.processID)
    }
    return FreshWindows(
      tracked: tracked, untracked: untracked,
      unattachedApps: unattached.map { $0.name ?? "pid \($0.processID)" }.sorted(),
      focusedID: frontmostFocusedWindow())
  }

  private func frontmostFocusedWindow() -> WindowID? {
    guard let front = workspace.frontmostProcessID else { return nil }
    let application = bridge.applicationElement(processID: front)
    return bridge.focusedWindow(of: application).flatMap(bridge.windowID(of:))
  }
}

import AppKit
import ApplicationServices
import TylerCore
import TylerServer

/// Reading every window again, for `tyler debug windows`.
extension AXBackend {
  package func freshWindows() -> FreshWindows {
    let tracked = snapshot()
    let trackedIDs = Set(tracked.map(\.id))
    var untracked: [WindowInfo] = []
    for processID in attachedProcessIDs {
      let application = AXBridge.applicationElement(processID: processID)
      for element in AXBridge.windows(of: application) {
        guard let windowID = AXBridge.windowID(of: element), !trackedIDs.contains(windowID),
          let info = WindowInfo.read(
            element, id: windowID, processID: processID, known: nil, isFocused: false)
        else { continue }
        untracked.append(info)
      }
    }
    let ownID = ProcessInfo.processInfo.processIdentifier
    let attached = Set(attachedProcessIDs)
    let unattached = NSWorkspace.shared.runningApplications.filter { app in
      app.activationPolicy == .regular && app.processIdentifier != ownID
        && !attached.contains(app.processIdentifier)
    }
    return FreshWindows(
      tracked: tracked, untracked: untracked,
      unattachedApps: unattached.map { $0.localizedName ?? "pid \($0.processIdentifier)" }.sorted(),
      focusedID: frontmostFocusedWindow())
  }

  private func frontmostFocusedWindow() -> WindowID? {
    guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
    let application = AXBridge.applicationElement(processID: front.processIdentifier)
    return AXBridge.focusedWindow(of: application).flatMap(AXBridge.windowID(of:))
  }
}

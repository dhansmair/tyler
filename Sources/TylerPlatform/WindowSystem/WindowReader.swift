import ApplicationServices
import TylerCore

/// Reads a window as its app reports it. Whether it has the focus is for the window system to
/// say, which knows every app.
@MainActor
struct WindowReader {
  let bridge: AXBridge
  let workspace: any WorkspaceClient

  /// In one round trip; `nil` if the frame can't be read. A window's app never changes, so an
  /// earlier read (`known`) gives its name; whether it is hidden is read each time.
  func read(
    _ element: AXUIElement, id: WindowID, processID: pid_t, known: WindowInfo?
  ) -> WindowInfo? {
    guard let attributes = bridge.windowAttributes(of: element) else { return nil }
    let app = workspace.runningApp(processID)
    return WindowInfo(
      id: id,
      processID: processID,
      appName: known?.appName ?? app?.name ?? "pid \(processID)",
      bundleID: known?.bundleID ?? app?.bundleID,
      title: attributes.title ?? "",
      frame: attributes.frame,
      kind: WindowKind.classify(
        role: attributes.role, subrole: attributes.subrole, buttons: attributes.buttons,
        isResizable: attributes.isResizable),
      isMinimized: attributes.isMinimized ?? false,
      isFullscreen: attributes.isFullscreen ?? false,
      isHidden: app?.isHidden ?? known?.isHidden ?? false,
      isFocused: false
    )
  }
}

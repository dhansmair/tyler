import ApplicationServices
import TylerCore

/// Reads a window as its app reports it. Whether it has the focus is for the window system to
/// say, which knows every app.
@MainActor
struct WindowReader {
  let bridge: AXBridge
  let workspace: any WorkspaceClient

  /// In one round trip; `nil` if the frame can't be read. A window's app never changes, so with an
  /// earlier read (`known`) the app isn't looked up again; whether it is hidden comes from there
  /// too, as the app's connection keeps it up to date.
  func read(
    _ element: AXUIElement, id: WindowID, processID: pid_t, known: WindowInfo?
  ) -> WindowInfo? {
    guard let attributes = bridge.windowAttributes(of: element) else { return nil }
    let app = known == nil ? workspace.runningApp(processID) : nil
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
      isHidden: known?.isHidden ?? app?.isHidden ?? false,
      isFocused: false
    )
  }
}

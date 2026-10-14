import ApplicationServices
import TylerCore

/// Reads a window as its app reports it.
@MainActor
struct WindowReader {
  let bridge: AXBridge
  let workspace: any WorkspaceClient

  /// In one round trip; `nil` if the frame can't be read. A window's app never changes, so with an
  /// earlier read (`known`) the app isn't looked up again.
  func read(
    _ element: AXUIElement, id: WindowID, processID: pid_t, known: WindowInfo?, isFocused: Bool
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
        role: attributes.role, subrole: attributes.subrole, buttons: attributes.buttons),
      isMinimized: attributes.isMinimized ?? false,
      isFullscreen: attributes.isFullscreen ?? false,
      isFocused: isFocused
    )
  }
}

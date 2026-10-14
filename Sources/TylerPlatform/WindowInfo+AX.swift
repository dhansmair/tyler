import AppKit
import ApplicationServices
import TylerCore

extension WindowInfo {
  /// A window as its app reports it, in one round trip; `nil` if the frame can't be read. A
  /// window's app never changes, so with an earlier read (`known`) the app isn't looked up again.
  static func read(
    _ element: AXUIElement, id: WindowID, processID: pid_t, known: WindowInfo?, isFocused: Bool
  ) -> WindowInfo? {
    guard let attributes = AXBridge.windowAttributes(of: element) else { return nil }
    let app = known == nil ? NSRunningApplication(processIdentifier: processID) : nil
    return WindowInfo(
      id: id,
      processID: processID,
      appName: known?.appName ?? app?.localizedName ?? "pid \(processID)",
      bundleID: known?.bundleID ?? app?.bundleIdentifier,
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

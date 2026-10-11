import CoreGraphics
import TylerCore

/// The strip layout: window sizes, and scrolling its view.
extension WindowManager {
  /// Sets the focused window's size in the strip layout. Other layouts keep it for when the
  /// workspace turns to the strip.
  public func setSize(_ choice: SizeChoice) -> Response {
    if let failure = beginCommand() { return failure }
    guard let windowID = registry.focusedID, workspaces.current.contains(windowID) else {
      return .error("the focused window is not tiled")
    }
    let size: WindowSize
    switch choice {
    case .set(let chosen): size = chosen
    case .next: size = workspaces.current.size(of: windowID).next
    }
    workspaces.current.setSize(size, of: windowID)
    let failures = applyLayout()
    guard failures == 0 else { return outcome(failures: failures) }
    return .message(
      workspaces.current.layout == .strip
        ? "size \(size.rawValue)" : "size \(size.rawValue) (used by the strip layout)")
  }
}

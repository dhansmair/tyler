import CoreGraphics
import TylerCore

package func makeWindow(
  id: UInt32,
  title: String = "",
  frame: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300),
  kind: WindowKind = .standard,
  isMinimized: Bool = false,
  isFullscreen: Bool = false,
  isFocused: Bool = false
) -> WindowInfo {
  WindowInfo(
    id: WindowID(id),
    processID: 500,
    appName: "App",
    title: title,
    frame: frame,
    kind: kind,
    isMinimized: isMinimized,
    isFullscreen: isFullscreen,
    isFocused: isFocused
  )
}

/// Standard windows `ids`, spread left to right on the primary display in that order.
package func spread(_ ids: [UInt32]) -> [WindowInfo] {
  ids.enumerated().map { index, windowID in
    makeWindow(id: windowID, frame: ManagerHarness.originalFrame(index: index))
  }
}

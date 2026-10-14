/// Why tylerd leaves the window at a point alone.
package enum PointerRefusal: String, Codable, CaseIterable, Sendable {
  case focusFollowsOff
  case tilingOff
  /// A slide, swipe or drag moves the windows.
  case busy
  case buttonHeld
  /// Outside every display's visible frame: the menu bar, the Dock, or off screen.
  case outsideDisplays
  case menuOpen
  case nothingThere
  /// A menu, the Dock or another window above the normal layer.
  case notANormalWindow
  /// Not tiled on a display's current workspace, nor floated: a parked window's sliver, or a
  /// window tylerd doesn't know.
  case notInView
  case alreadyFocused

  /// What it means, for `tyler debug at`.
  package var explanation: String {
    switch self {
    case .focusFollowsOff: "focus follows mouse is off (mouse.focus-follows)"
    case .tilingOff: "tiling is off"
    case .busy: "a slide, swipe or drag is moving the windows"
    case .buttonHeld: "a mouse button is held"
    case .outsideDisplays: "the point is outside every display's visible frame"
    case .menuOpen: "a menu is open"
    case .nothingThere: "there is no window at the point"
    case .notANormalWindow: "the window on top is not a normal window (a menu, the Dock)"
    case .notInView: "the window on top is not tiled in view, nor floated"
    case .alreadyFocused: "the window on top has the focus already"
    }
  }
}

/// Whether a press with the modifier grabs the window at a point, and whether focus follows the
/// mouse to it once the pointer rests there. Pure: the server fills in what it knows, and both the
/// real decisions and `tyler debug at` read the verdicts here, so the two can't disagree. The
/// defaults are those under which nothing is refused.
package struct PointerCheck: Codable, Equatable, Sendable {
  package var focusFollows = true
  package var isTiling = true
  /// No slide, swipe or drag moves the windows.
  package var isIdle = true
  package var isButtonHeld = false
  /// The point is inside a display's visible frame.
  package var isInsideDisplay = true
  package var isMenuOpen = false
  /// The topmost on-screen window at the point, of any app and layer.
  package var topmost: StackedWindow?
  /// The windows in their slots on each display's current workspace, and the floated ones.
  package var inView: Set<WindowID> = []
  package var focusedID: WindowID?

  package init() {}

  /// Whether a press with the modifier grabs the window: one in view, at the normal layer,
  /// inside a display's visible frame, with tiling on and nothing else moving the windows.
  package var grab: PointerVerdict {
    if !isTiling { return .refused(.tilingOff) }
    if !isIdle { return .refused(.busy) }
    if !isInsideDisplay { return .refused(.outsideDisplays) }
    return windowOnTop
  }

  /// Whether focus follows the mouse to the window: as for `grab`, and also not while a button is
  /// held or a menu is open (moving off a menu would close it), and not to the focused window.
  package var focus: PointerVerdict {
    if !focusFollows { return .refused(.focusFollowsOff) }
    if !isTiling { return .refused(.tilingOff) }
    if !isIdle { return .refused(.busy) }
    if isButtonHeld { return .refused(.buttonHeld) }
    if !isInsideDisplay { return .refused(.outsideDisplays) }
    if isMenuOpen { return .refused(.menuOpen) }
    if let topmost, topmost.id == focusedID, topmost.layer == PointerFocus.normalLayer {
      return .refused(.alreadyFocused)
    }
    return windowOnTop
  }

  private var windowOnTop: PointerVerdict {
    guard let topmost else { return .refused(.nothingThere) }
    guard topmost.layer == PointerFocus.normalLayer else { return .refused(.notANormalWindow) }
    guard inView.contains(topmost.id) else { return .refused(.notInView) }
    return .window(topmost.id)
  }
}

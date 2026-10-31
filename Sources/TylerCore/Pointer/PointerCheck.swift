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
  /// The current workspace of the display at the point holds no window.
  package var isWorkspaceEmpty = false
  /// Something the window list leaves out covers the point: an overlay, or the lock screen.
  package var isCovered = false
  /// The focused window is on no workspace, such as a floated one. It keeps the focus over an
  /// empty workspace, so the focused display would part from the keys.
  package var isFocusOffWorkspaces = false

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
  /// held or a menu is open (moving off a menu would close it), and not to the focused window. Over
  /// bare wallpaper of an empty workspace, the workspace gets the focus, as switching to it would,
  /// so the focused display and the keys never part. A workspace with windows gets the focus
  /// through the window rested on.
  package var focus: PointerVerdict {
    if let restRefusal { return .refused(restRefusal) }
    if let topmost, topmost.id == focusedID, topmost.layer == PointerFocus.normalLayer {
      return .refused(.alreadyFocused)
    }
    if isWorkspaceEmpty, topmost == nil, !isCovered, !isFocusOffWorkspaces {
      return .emptyWorkspace
    }
    return windowOnTop
  }

  /// Why a rest does nothing here, whatever is under the pointer.
  private var restRefusal: PointerRefusal? {
    if !focusFollows { return .focusFollowsOff }
    if !isTiling { return .tilingOff }
    if !isIdle { return .busy }
    if isButtonHeld { return .buttonHeld }
    if !isInsideDisplay { return .outsideDisplays }
    if isMenuOpen { return .menuOpen }
    return nil
  }

  private var windowOnTop: PointerVerdict {
    guard let topmost else { return .refused(.nothingThere) }
    guard topmost.layer == PointerFocus.normalLayer else { return .refused(.notANormalWindow) }
    guard inView.contains(topmost.id) else { return .refused(.notInView) }
    return .window(topmost.id)
  }
}

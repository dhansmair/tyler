import CoreGraphics

/// Which window focus follows the pointer to, once it has come to rest. Pure: the server
/// asks the window server what is under the pointer and focuses the result.
package enum PointerFocus {
  /// The layer of normal application windows.
  package static let normalLayer = 0

  /// The cursor's layer (`kCGCursorWindowLevel`), second from the top.
  package static let cursorLayer = 2_147_483_630

  /// Whether a window is an overlay that says nothing about what is under the pointer, so clicks
  /// go through it:
  /// - one above the normal layer that covers exactly a whole display. The Dock (layer 20) and
  ///   Notification Centre (layer 21) each have one on the display they are on, above every app
  ///   window. The manager only follows the pointer inside a display's visible frame, which leaves
  ///   the Dock itself out.
  /// - one at the cursor's layer or above. While the screen is shared, the cursor is a window
  ///   under the pointer, so it would always be on top; the privacy indicators sit there too.
  ///
  /// See `devdocs/macos-behaviour.md`.
  package static func isOverlay(layer: Int, frame: CGRect, displayFrames: [CGRect]) -> Bool {
    layer >= cursorLayer || (layer > normalLayer && displayFrames.contains(frame))
  }

  /// The window to focus, or `nil` to leave the focus alone. Only a window in `inView` counts: one
  /// in view on a display's current workspace, or floated. A parked window's sliver at the edge
  /// of a display never does, since focusing it would switch workspaces or scroll the strip.
  /// Nothing is focused while a menu is open, so moving off it doesn't close it, or when `topmost`
  /// is above the normal layer or focused already.
  package static func target(
    under topmost: StackedWindow?, isMenuOpen: Bool, inView: Set<WindowID>, focusedID: WindowID?
  ) -> WindowID? {
    var check = PointerCheck()
    check.isMenuOpen = isMenuOpen
    check.topmost = topmost
    check.inView = inView
    check.focusedID = focusedID
    return check.focus.window
  }
}

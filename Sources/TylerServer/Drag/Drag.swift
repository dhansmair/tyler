import CoreGraphics
import TylerCore

/// A tiled window the user is dragging with the primary button down: what it decides
/// (`DragSession`) and the pacing of following a resize.
struct Drag {
  var session: DragSession
  /// The newest frame of a resize that the layout hasn't followed yet.
  var pendingFrame: CGRect?
  /// The newest pointer location of a grab (with the modifier, or of a gap) not acted on yet.
  var pendingLocation: CGPoint?
  /// Follows resizes, and the pointer of a grab, at most once per `mouse.follow-interval`.
  var throttle = Throttle()
  /// The windows the preview is moving, while it moves them.
  var preview: DragPreview?
  /// How many previews have moved windows, to tell a finished one from its successor.
  var previewCount = 0

  var windowID: WindowID { session.windowID }
}

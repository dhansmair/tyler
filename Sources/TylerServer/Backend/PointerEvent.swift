import CoreGraphics
import TylerCore

/// Something the mouse or trackpad did that isn't about one window. Window moves and resizes
/// arrive through `WindowBackend`; this carries what tylerd can't learn from the windows.
package enum PointerEvent: Equatable, Sendable {
  /// The primary (left) button went up, anywhere on screen. `location` is in Accessibility
  /// coordinates.
  case primaryButtonReleased(location: CGPoint)
  /// The pointer moved with the primary button down, anywhere on screen. `location` is in
  /// Accessibility coordinates.
  case primaryButtonDragged(location: CGPoint)
  /// A sideways swipe on the trackpad, with the number of fingers from the config, and where
  /// the pointer is, in Accessibility coordinates.
  case swipe(SwipeUpdate, location: CGPoint)
  /// The pointer moved with no button down, anywhere on screen. `location` is in Accessibility
  /// coordinates. Only reported while `PointerWatch.moves` is on.
  case moved(location: CGPoint)
  /// A drag with the modifier, or in a gap, began: the button went down at `location`, in
  /// Accessibility coordinates, over what `canCapture` allowed, and the pointer has moved since.
  /// The app under the pointer sees none of the gesture.
  case modifierDragBegan(ModifierGesture.Kind, location: CGPoint)
  /// The pointer moved during a drag with the modifier.
  case modifierDragMoved(location: CGPoint)
  /// The button of a drag with the modifier went up, or macOS stopped reporting the drag.
  case modifierDragEnded(location: CGPoint)
}

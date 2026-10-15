import CoreGraphics

/// What releasing a drag does to the lists.
package enum DragDrop: Equatable, Sendable {
  /// The window joins the current workspace of another display.
  case arrive(Arrival)
  /// The layout of the display at `position` follows the window's new size.
  case resize(position: Int, frame: CGRect)
  /// The window moves to `place` in the list of the display at `position`.
  case move(position: Int, place: ListPlace)
  /// Nothing changes: the window goes back to its slot.
  case back
}

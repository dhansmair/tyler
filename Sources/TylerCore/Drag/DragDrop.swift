import CoreGraphics

/// What releasing a drag does to the lists.
package enum DragDrop: Equatable, Sendable {
  /// The window joins the current workspace of another display.
  case arrive(Arrival)
  /// The layout of the display at `position` follows the window's new size.
  case resize(position: Int, frame: CGRect)
  /// The window and `target` swap places in the list of the display at `position`.
  case swap(position: Int, target: WindowID)
  /// Nothing changes: the window goes back to its slot.
  case back
}

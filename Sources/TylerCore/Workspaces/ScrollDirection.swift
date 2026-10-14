import CoreGraphics

/// Which way the view scrolls when changing workspaces. The workspaces sit in a row, side by
/// side (a horizontal slide, because macOS won't let windows leave through the top or bottom of
/// the display; see `Parking`). Moving to the `next` workspace slides the current windows out to
/// the left while the next workspace's windows come in from the right.
package enum ScrollDirection: Equatable, Sendable {
  case prev
  case next

  /// How far outgoing windows travel horizontally for a visible frame of `width`; incoming
  /// windows start the same distance away on the opposite side.
  package func outgoingOffset(width: CGFloat) -> CGFloat {
    self == .next ? -width : width
  }

  package var opposite: ScrollDirection {
    self == .next ? .prev : .next
  }

  /// The neighbour that content moved by `offset` display widths brings into view: moving left
  /// (negative) shows the next one, moving right the previous one, and nothing at 0.
  package init?(revealedBy offset: Double) {
    guard offset != 0 else { return nil }
    self = offset < 0 ? .next : .prev
  }
}

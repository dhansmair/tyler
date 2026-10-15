import CoreGraphics

/// Where a drag with the modifier started, which the pointer's moves are measured from.
package struct ModifierGrab: Equatable, Sendable {
  package let kind: ModifierGesture.Kind
  /// The pointer at the press.
  package let start: CGPoint
  /// The window's frame at the press; for a tiled window's resize, its slot's.
  package let frame: CGRect
  /// The edges a resize moves: those of the quarter of the window that was grabbed, for a tiled
  /// window those between windows.
  package let edges: ResizeEdges
  /// A floated window moves and resizes freely; a tiled one through the layout.
  package let isFloated: Bool

  package init(
    kind: ModifierGesture.Kind, start: CGPoint, frame: CGRect, edges: ResizeEdges,
    isFloated: Bool
  ) {
    self.kind = kind
    self.start = start
    self.frame = frame
    self.edges = edges
    self.isFloated = isFloated
  }
}

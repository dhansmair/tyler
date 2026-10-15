import CoreGraphics

/// The edges of a window that a resize with the modifier moves: one side and one end, picked by
/// the quarter of the window that was grabbed, so dragging near a corner moves that corner.
package struct ResizeEdges: OptionSet, Hashable, Sendable {
  package let rawValue: Int

  package init(rawValue: Int) {
    self.rawValue = rawValue
  }

  package static let left = Self(rawValue: 1 << 0)
  package static let right = Self(rawValue: 1 << 1)
  package static let top = Self(rawValue: 1 << 2)
  package static let bottom = Self(rawValue: 1 << 3)

  /// The smallest width and height a resize leaves, in points.
  package static let minimumSide: CGFloat = 50

  /// The edges nearest to `point` in `frame` (Accessibility coordinates: y grows downward). A
  /// point exactly in the middle counts toward the right and the bottom.
  package init(grabbedAt point: CGPoint, in frame: CGRect) {
    self = [point.x < frame.midX ? .left : .right, point.y < frame.midY ? .top : .bottom]
  }

  /// For a tiled window at `frame` among the frames of the other windows in view: each of these
  /// edges with no window beyond it, swapped for the opposite edge if that one has a window
  /// beyond it. An edge on the display's border stays where it is, so grabbing the half beside
  /// it could only ever shrink the window.
  package func towardNeighbours(of frame: CGRect, among others: [CGRect]) -> Self {
    var edges = self
    let opposites: [(Self, Self)] = [
      (.left, .right), (.right, .left), (.top, .bottom), (.bottom, .top),
    ]
    for (edge, opposite) in opposites where contains(edge) {
      guard !frame.hasWindow(beyond: edge, among: others),
        frame.hasWindow(beyond: opposite, among: others)
      else { continue }
      edges.remove(edge)
      edges.insert(opposite)
    }
    return edges
  }
}

extension CGRect {
  fileprivate func hasWindow(beyond edge: ResizeEdges, among others: [CGRect]) -> Bool {
    others.contains { other in
      let besideVertically = other.minY < maxY && other.maxY > minY
      let besideHorizontally = other.minX < maxX && other.maxX > minX
      switch edge {
      case .left: return besideVertically && other.maxX <= minX
      case .right: return besideVertically && other.minX >= maxX
      case .top: return besideHorizontally && other.maxY <= minY
      case .bottom: return besideHorizontally && other.minY >= maxY
      default: return false
      }
    }
  }
}

extension CGRect {
  /// This rect with `edges` moved by `delta` and the other edges kept, never narrower or shorter
  /// than `ResizeEdges.minimumSide` (or the rect itself, if it is smaller already).
  package func resizing(_ edges: ResizeEdges, by delta: CGVector) -> CGRect {
    var left = minX
    var right = maxX
    var top = minY
    var bottom = maxY
    let minimumWidth = Swift.min(width, ResizeEdges.minimumSide)
    let minimumHeight = Swift.min(height, ResizeEdges.minimumSide)
    if edges.contains(.left) { left = Swift.min(left + delta.dx, right - minimumWidth) }
    if edges.contains(.right) { right = Swift.max(right + delta.dx, left + minimumWidth) }
    if edges.contains(.top) { top = Swift.min(top + delta.dy, bottom - minimumHeight) }
    if edges.contains(.bottom) { bottom = Swift.max(bottom + delta.dy, top + minimumHeight) }
    return CGRect(x: left, y: top, width: right - left, height: bottom - top)
  }
}

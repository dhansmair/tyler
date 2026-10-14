import CoreGraphics

/// A press in the gap between two tiled windows: the window before the gap (to its left, or
/// above it) and its edge that faces the gap. Dragging that edge moves the divider, and the
/// layout moves the window on the other side along.
package struct GapGrab: Equatable, Sendable {
  package let windowID: WindowID
  /// `.right` for a gap beside the window, `.bottom` for one below it.
  package let edge: ResizeEdges
  /// The gap along that edge, as long as the window's side, and as wide as the space to the
  /// next window.
  package let area: CGRect

  package init(windowID: WindowID, edge: ResizeEdges, area: CGRect) {
    self.windowID = windowID
    self.edge = edge
    self.area = area
  }

  /// The gap at `point` between two of `slots`, or `nil` if `point` is in a slot, at the outer
  /// edge of the tiled area, or where gaps cross (no window lies on either side there).
  package init?(at point: CGPoint, among slots: [Placement]) {
    guard !slots.contains(where: { $0.frame.contains(point) }) else { return nil }
    if let gap = Self.gap(before: point.x, at: point.y, in: slots, isSideways: true) {
      self = gap
    } else if let gap = Self.gap(before: point.y, at: point.x, in: slots, isSideways: false) {
      self = gap
    } else {
      return nil
    }
  }

  /// The gap after the slot ending nearest before `position` along an axis, up to the nearest
  /// slot starting after it; both cover `crossing` on the other axis.
  private static func gap(
    before position: CGFloat, at crossing: CGFloat, in slots: [Placement], isSideways: Bool
  ) -> GapGrab? {
    let covering = slots.map { Span($0, isSideways: isSideways) }
      .filter { $0.crossing.contains(crossing) }
    guard let before = covering.filter({ $0.end <= position }).max(by: { $0.end < $1.end }),
      let after = covering.map(\.start).filter({ $0 >= position }).min()
    else { return nil }
    let across = before.crossing
    let area =
      isSideways
      ? CGRect(
        x: before.end, y: across.lowerBound, width: after - before.end,
        height: across.upperBound - across.lowerBound)
      : CGRect(
        x: across.lowerBound, y: before.end, width: across.upperBound - across.lowerBound,
        height: after - before.end)
    return GapGrab(windowID: before.id, edge: isSideways ? .right : .bottom, area: area)
  }

  /// A slot along one axis, sideways (x) or upright (y), and the range it covers on the other.
  private struct Span {
    let id: WindowID
    let start: CGFloat
    let end: CGFloat
    let crossing: Range<CGFloat>

    init(_ slot: Placement, isSideways: Bool) {
      let frame = slot.frame
      id = slot.id
      start = isSideways ? frame.minX : frame.minY
      end = isSideways ? frame.maxX : frame.maxY
      crossing = isSideways ? frame.minY..<frame.maxY : frame.minX..<frame.maxX
    }
  }
}

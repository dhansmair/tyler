import CoreGraphics

/// Settling a pan on one of a few positions, in one dimension. The units are the caller's
/// (points for the workspace row, later the strip layout's columns): an offset follows the
/// fingers, and on release the pan settles on a snap point.
public enum Snap {
  /// Where a pan released at `offset`, moving at `velocity` (units per second), comes to rest:
  /// the nearest point, unless the release was a flick of at least `flickVelocity`, which goes on
  /// to the next point in its direction (never further). Returns `offset` itself if there are no
  /// points.
  public static func target(
    offset: CGFloat, velocity: CGFloat, points: [CGFloat], flickVelocity: CGFloat
  ) -> CGFloat {
    guard let nearest = points.min(by: { abs($0 - offset) < abs($1 - offset) }) else {
      return offset
    }
    guard abs(velocity) >= flickVelocity else { return nearest }
    let ahead = velocity > 0 ? points.filter { $0 > offset } : points.filter { $0 < offset }
    let next = velocity > 0 ? ahead.min() : ahead.max()
    return next ?? nearest
  }

  /// `offset` with resistance past the outermost points: inside their range it is unchanged,
  /// beyond it only `resistance` of the extra distance counts, so the content gives a little and
  /// shows there is nothing further.
  public static func resisted(
    _ offset: CGFloat, within points: [CGFloat], resistance: CGFloat = 0.2
  ) -> CGFloat {
    guard let low = points.min(), let high = points.max() else { return offset }
    if offset > high { return high + (offset - high) * resistance }
    if offset < low { return low - (low - offset) * resistance }
    return offset
  }
}

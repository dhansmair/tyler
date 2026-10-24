import CoreGraphics

/// Where a window goes when it is floated from its slot: a little toward the middle of the area
/// windows tile in, so that none of its edges lines up with the tiled windows that take over the
/// slot, and it is plain to see that it floats.
package enum FloatedFrame {
  /// How far the window moves toward the middle on an axis its slot doesn't span.
  static let offset: CGFloat = 30
  /// How far each edge moves in on an axis the slot spans, where moving would take the window
  /// past the area. More than the offset, so the margin reads as a float, not a gap.
  static let margin: CGFloat = 2 * offset
  /// A side shorter than this after shrinking shrinks only down to it.
  static let minimumSide: CGFloat = 200

  /// On an axis where the slot is centred without spanning it, the window moves right or down.
  package static func frame(leaving slot: CGRect, in area: CGRect) -> CGRect {
    let (left, width) = place(slot.minX, slot.width, in: area.minX, area.width)
    let (top, height) = place(slot.minY, slot.height, in: area.minY, area.height)
    return CGRect(x: left, y: top, width: width, height: height)
  }

  /// The start and length on one axis.
  private static func place(
    _ start: CGFloat, _ length: CGFloat, in areaStart: CGFloat, _ areaLength: CGFloat
  ) -> (CGFloat, CGFloat) {
    let spans = start <= areaStart + 1 && start + length >= areaStart + areaLength - 1
    if spans {
      let inset = max(0, min(margin, (length - minimumSide) / 2)).rounded()
      return (start + inset, length - 2 * inset)
    }
    let middle = areaStart + areaLength / 2
    let moved = start + (start + length / 2 > middle ? -offset : offset)
    return (moved.clamped(to: areaStart...max(areaStart, areaStart + areaLength - length)), length)
  }
}

import CoreGraphics

package enum DisplayGeometry {
  /// The flip between the two coordinate systems is its own inverse.
  package static func appKitRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
    axRect(fromAppKit: rect, primaryScreenHeight: primaryScreenHeight)
  }

  /// Converts an AppKit rectangle (origin bottom-left of the primary display, y grows upwards)
  /// to Accessibility coordinates (origin top-left, y grows downwards).
  package static func axRect(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
    CGRect(
      x: rect.minX,
      y: primaryScreenHeight - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }

  /// The display a window belongs to: the one it overlaps most, or, if it overlaps none (for
  /// example a parked window), the one whose centre is closest. Ties go to the earlier display.
  package static func display(
    containing frame: CGRect, in displays: [DisplayInfo]
  ) -> DisplayInfo? {
    var best: (display: DisplayInfo, overlap: CGFloat)?
    for display in displays {
      let intersection = display.frame.intersection(frame)
      let overlap = intersection.isNull ? 0 : intersection.width * intersection.height
      if overlap > (best?.overlap ?? 0) {
        best = (display, overlap)
      }
    }
    if let best { return best.display }
    return displays.min {
      distance(from: frame, to: $0.frame) < distance(from: frame, to: $1.frame)
    }
  }

  /// `frame` on `source` moved to `target`, at the same offset from the top left of the visible
  /// frame, then shrunk and moved as little as it takes to lie within the target's visible frame.
  package static func frame(
    _ frame: CGRect, carriedFrom source: DisplayInfo, to target: DisplayInfo
  ) -> CGRect {
    let area = target.visibleFrame
    let size = CGSize(width: min(frame.width, area.width), height: min(frame.height, area.height))
    let left = area.minX + frame.minX - source.visibleFrame.minX
    let top = area.minY + frame.minY - source.visibleFrame.minY
    return CGRect(
      x: left.clamped(to: area.minX...area.maxX - size.width),
      y: top.clamped(to: area.minY...area.maxY - size.height), width: size.width,
      height: size.height)
  }

  private static func distance(from first: CGRect, to second: CGRect) -> CGFloat {
    let deltaX = first.midX - second.midX
    let deltaY = first.midY - second.midY
    return (deltaX * deltaX + deltaY * deltaY).squareRoot()
  }
}

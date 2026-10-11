import CoreGraphics

/// Names a display across unplugging, sleep and restarts: macOS gives each display a UUID that
/// stays the same, while its `CGDirectDisplayID` may change after a reboot.
public struct DisplayKey: Hashable, Codable, Sendable, CustomStringConvertible {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

/// One physical display, in Accessibility coordinates (origin top-left of the primary display).
public struct DisplayInfo: Codable, Equatable, Sendable, Identifiable {
  public var id: UInt32
  public var key: DisplayKey
  public var frame: CGRect
  /// The area not covered by the menu bar and Dock.
  public var visibleFrame: CGRect

  /// A display; without a `key`, its id names it.
  public init(id: UInt32, key: DisplayKey? = nil, frame: CGRect, visibleFrame: CGRect) {
    self.id = id
    self.key = key ?? DisplayKey("\(id)")
    self.frame = frame
    self.visibleFrame = visibleFrame
  }
}

public enum DisplayGeometry {
  /// Converts an AppKit rectangle (origin bottom-left of the primary display, y grows upwards)
  /// to Accessibility coordinates (origin top-left, y grows downwards).
  public static func axRect(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
    CGRect(
      x: rect.minX,
      y: primaryScreenHeight - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }

  /// The display a window belongs to: the one it overlaps most, or, if it overlaps none (for
  /// example a parked window), the one whose centre is closest. Ties go to the earlier display.
  public static func display(containing frame: CGRect, in displays: [DisplayInfo]) -> DisplayInfo? {
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

  private static func distance(from first: CGRect, to second: CGRect) -> CGFloat {
    let deltaX = first.midX - second.midX
    let deltaY = first.midY - second.midY
    return (deltaX * deltaX + deltaY * deltaY).squareRoot()
  }
}

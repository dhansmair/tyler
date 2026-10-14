import CoreGraphics

/// One physical display, in Accessibility coordinates (origin top-left of the primary display).
package struct DisplayInfo: Codable, Equatable, Sendable, Identifiable {
  package var id: UInt32
  package var key: DisplayKey
  package var frame: CGRect
  /// The area not covered by the menu bar and Dock.
  package var visibleFrame: CGRect
  /// The sides where another display lies beside this one (see `DisplayArrangement.sided`).
  package var neighbours: Set<DisplaySide> = []
  /// The edge where windows of parked workspaces wait (see `Parking`).
  package var parkingEdge: DisplaySide = .right

  /// A display; without a `key`, its id names it.
  package init(id: UInt32, key: DisplayKey? = nil, frame: CGRect, visibleFrame: CGRect) {
    self.id = id
    self.key = key ?? DisplayKey("\(id)")
    self.frame = frame
    self.visibleFrame = visibleFrame
  }
}

extension DisplayInfo {
  /// Whether `frame` counts as in view: any of it is on the visible frame. A frame reaching past
  /// an edge with a neighbouring display doesn't count, since the window would reach onto that
  /// display (where macOS may cut it to that display's height).
  package func shows(_ frame: CGRect) -> Bool {
    let shown = visibleFrame.intersection(frame)
    guard !shown.isNull, shown.width >= 1, shown.height >= 1 else { return false }
    let reachesPastLeft = frame.minX < visibleFrame.minX && neighbours.contains(.left)
    let reachesPastRight = frame.maxX > visibleFrame.maxX && neighbours.contains(.right)
    return !reachesPastLeft && !reachesPastRight
  }
}

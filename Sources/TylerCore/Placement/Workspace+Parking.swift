import CoreGraphics

extension Workspace {
  /// Where every window rests on `display`: the windows in view in their slots, the others
  /// parked at the display's edge, keeping the size they'll have in view.
  package func restingPlacements(on display: DisplayInfo, gaps: LayoutGaps) -> [Placement] {
    let area = display.visibleFrame
    return arrangement(in: area, gaps: gaps).map { placement in
      display.shows(placement.frame)
        ? placement
        : Placement(id: placement.id, frame: Parking.frame(for: placement.frame, on: display))
    }
  }
}

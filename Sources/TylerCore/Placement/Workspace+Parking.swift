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

  /// Where the floating windows that can be seen go when the workspace comes onto `display`:
  /// where each was when it left the screen, or, for one it doesn't know that of, the frame
  /// `current` gives. A frame parked at the display's edge is pulled onto it, and one on another
  /// of `displays` (the workspace moved display) is carried over to the same place.
  package func floatingPlacements(
    on display: DisplayInfo, among displays: [DisplayInfo], current: (WindowID) -> CGRect?
  ) -> [Placement] {
    shownFloating.compactMap { windowID in
      (floatingFrame(of: windowID) ?? current(windowID)).map { frame in
        Placement(id: windowID, frame: Self.frameBrought(frame, onto: display, from: displays))
      }
    }
  }

  private static func frameBrought(
    _ frame: CGRect, onto display: DisplayInfo, from displays: [DisplayInfo]
  ) -> CGRect {
    if Parking.isParked(frame, on: display) { return Parking.pulledIn(frame, on: display) }
    guard let source = DisplayGeometry.display(containing: frame, in: displays),
      source.key != display.key
    else { return frame }
    let shown = Parking.isParked(frame, on: source) ? Parking.pulledIn(frame, on: source) : frame
    return DisplayGeometry.frame(shown, carriedFrom: source, to: display)
  }
}

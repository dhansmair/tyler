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
  /// `current` gives, pulled onto the display.
  package func floatingPlacements(
    on display: DisplayInfo, current: (WindowID) -> CGRect?
  ) -> [Placement] {
    shownFloating.compactMap { windowID in
      let frame =
        floatingFrame(of: windowID)
        ?? current(windowID).map { Parking.pulledIn($0, on: display) }
      return frame.map { Placement(id: windowID, frame: $0) }
    }
  }
}

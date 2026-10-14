import CoreGraphics

/// Every display's row of workspaces laid out on the connected displays: where tiling puts each
/// window right now. Its queries answer for the moment it was built.
package struct TilingSnapshot: Sendable {
  package let rows: DisplayRows
  package let gaps: LayoutGaps
  private let displays: [DisplayInfo]

  /// `displays` are the connected ones, arranged (see `DisplayArrangement.sided`); a row whose
  /// display isn't among them is left out of every answer.
  package init(rows: DisplayRows, displays: [DisplayInfo], gaps: LayoutGaps) {
    self.rows = rows
    self.displays = displays
    self.gaps = gaps
  }

  package func display(at position: Int) -> DisplayInfo? {
    let key = rows.entries[position].key
    return displays.first { $0.key == key }
  }

  /// The position in `rows` of the display under `location`, if it is connected.
  package func position(under location: CGPoint) -> Int? {
    displays.first { $0.frame.contains(location) }.flatMap { rows.position(of: $0.key) }
  }

  /// The position in `rows` of the display that has `windowID` on its current workspace; `nil`
  /// if the window is on a parked workspace or none.
  package func onScreenPosition(of windowID: WindowID) -> Int? {
    guard let location = rows.location(of: windowID),
      location.index == rows[location.position].currentIndex
    else { return nil }
    return location.position
  }

  /// The windows in view and their slots on the current workspace holding `windowID`; `nil` if
  /// the window isn't on a current workspace or its display isn't connected.
  package func currentPlacements(holding windowID: WindowID) -> [Placement]? {
    guard let position = onScreenPosition(of: windowID), let display = display(at: position)
    else { return nil }
    return rows[position].current.placements(on: display, gaps: gaps)
  }

  /// `nil` if the window isn't tiled on a current workspace, or is out of view.
  package func slot(of windowID: WindowID) -> Placement? {
    currentPlacements(holding: windowID)?.first { $0.id == windowID }
  }

  package func restingPlacements(at position: Int) -> [Placement] {
    guard let display = display(at: position) else { return [] }
    return rows[position].current.restingPlacements(on: display, gaps: gaps)
  }

  /// The resting placements of each display's current workspace, of the displays `keys` only if
  /// given.
  package func restingPlacements(on keys: Set<DisplayKey>? = nil) -> [Placement] {
    rows.entries.indices.flatMap { position in
      keys?.contains(rows.entries[position].key) ?? true ? restingPlacements(at: position) : []
    }
  }

  /// The windows of each display's current workspace that are out of view (only a scrolling
  /// layout has any), which wait parked.
  package var offViewWindows: Set<WindowID> {
    Set(
      rows.entries.indices.flatMap { position in
        display(at: position).map { rows[position].current.offView(on: $0, gaps: gaps) } ?? []
      })
  }

  /// The tiled windows in their slots on each display's current workspace.
  package var tiledWindowsInView: Set<WindowID> {
    Set(
      rows.entries.indices.flatMap { position in
        display(at: position).map { rows[position].current.placements(on: $0, gaps: gaps) } ?? []
      }.map(\.id))
  }

  /// Where a window of a parked workspace waits: the parking spot of its slot, on that
  /// workspace's display. A window without a slot there (it is out of view) waits as if at the
  /// top left of the visible frame with `size`, so one arriving from another display waits at a
  /// height where this display is. `nil` if it isn't on a workspace or its display isn't
  /// connected.
  package func parkingPlacement(of windowID: WindowID, size: CGSize) -> Placement? {
    guard let location = rows.location(of: windowID), let display = display(at: location.position)
    else { return nil }
    let workspace = rows[location.position][location.index]
    let slot =
      workspace.placements(on: display, gaps: gaps).first { $0.id == windowID }?.frame
      ?? CGRect(origin: display.visibleFrame.origin, size: size)
    return Placement(id: windowID, frame: Parking.frame(for: slot, on: display))
  }
}

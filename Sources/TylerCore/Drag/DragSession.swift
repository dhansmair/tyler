import CoreGraphics

/// A tiled window the user is dragging, and what the preview shows of where it would go: there
/// is always exactly one open slot, the one the window would take. It decides; the caller moves
/// the windows and changes the lists.
package struct DragSession: Equatable, Sendable {
  package let windowID: WindowID
  /// Whether the window changed size, not only place. A resize never moves it to another place.
  package var isResize = false
  /// Where a window dragged by its title bar or its edges was when the drag began.
  package let startFrame: CGRect?
  /// For a drag with the modifier, where it started; `nil` for a window dragged by its title bar
  /// or its edges.
  package var grab: ModifierGrab?
  /// Where in its own display's list the preview shows the window going in; `nil` while it shows
  /// the window in its own place.
  package private(set) var previewPlace: ListPlace?
  /// Where the window would go in on another display, while the pointer is over it; the preview
  /// has made room for it there.
  package private(set) var arrival: Arrival?

  package init(windowID: WindowID, startFrame: CGRect? = nil) {
    self.windowID = windowID
    self.startFrame = startFrame
  }

  /// The place where the window would go in on another display if released at `location`: the
  /// one whose slot is under the pointer (see `Workspace.arrivalIndex`). In a gap, it is the place
  /// the preview shows already, or last. `nil` while the pointer isn't over another display.
  package func arrival(at location: CGPoint, in tiling: TilingSnapshot) -> Arrival? {
    guard let position = tiling.position(under: location),
      position != tiling.rows.location(of: windowID)?.position,
      let display = tiling.display(at: position)
    else { return nil }
    let workspace = tiling.rows[position].current
    let shown = arrival.flatMap { $0.position == position ? $0.index : nil }
    let index =
      workspace.arrivalIndex(of: windowID, at: location, on: display, gaps: tiling.gaps)
      ?? shown ?? workspace.count
    return Arrival(position: position, index: index)
  }

  /// Where on its own display the window goes in if released at `location`: the place whose
  /// slot is under the pointer (see `Workspace.dropPlace`). In a gap, it is the place the
  /// preview shows already. `nil` over its own slot or outside its display's visible area.
  package func place(at location: CGPoint, in tiling: TilingSnapshot) -> ListPlace? {
    guard let position = tiling.onScreenPosition(of: windowID),
      let display = tiling.display(at: position), display.visibleFrame.contains(location)
    else { return nil }
    let workspace = tiling.rows[position].current
    guard
      let place = workspace.dropPlace(
        for: windowID, at: location, on: display, gaps: tiling.gaps)
    else { return previewPlace }
    return place == workspace.place(of: windowID) ? nil : place
  }

  /// Over the window's own display: its windows lay out as if the window were at the place a
  /// release at `location` would put it, leaving its slot open. Returns the windows that move
  /// for that; empty while the place stays the same.
  package mutating func previewMove(
    at location: CGPoint, in tiling: TilingSnapshot
  ) -> [Placement] {
    let place = place(at: location, in: tiling)
    guard place != previewPlace else { return [] }
    let shown = previewPlacements(in: tiling)
    previewPlace = place
    return previewPlacements(in: tiling).filter { !shown.contains($0) }
  }

  /// Puts back the windows the move preview moved; the dragged window stays under the pointer.
  package mutating func undoMovePreview(in tiling: TilingSnapshot) -> [Placement] {
    guard previewPlace != nil else { return [] }
    let shown = previewPlacements(in: tiling)
    previewPlace = nil
    return previewPlacements(in: tiling).filter { !shown.contains($0) }
  }

  /// Forgets the move preview without moving its windows: the list it was worked out from has
  /// changed (a window closed).
  package mutating func forgetMovePreview() {
    previewPlace = nil
  }

  /// Where the move preview shows the windows of the dragged window's display, the dragged
  /// window left out.
  private func previewPlacements(in tiling: TilingSnapshot) -> [Placement] {
    guard let position = tiling.onScreenPosition(of: windowID),
      let display = tiling.display(at: position)
    else { return [] }
    var workspace = tiling.rows[position].current
    if let previewPlace { workspace.move(windowID, to: previewPlace) }
    return workspace.restingPlacements(on: display, gaps: tiling.gaps).filter {
      $0.id != windowID
    }
  }

  /// Makes room for the window on another display: the windows of its own display close up as if
  /// it had left, and those of the display under the pointer lay out as if it were in at
  /// `arrival`, leaving its slot open. Empty if that is shown already.
  package mutating func preview(_ arrival: Arrival, in tiling: TilingSnapshot) -> [Placement] {
    guard arrival != self.arrival, let source = tiling.onScreenPosition(of: windowID) else {
      return []
    }
    var placements: [Placement] = []
    if self.arrival == nil, let display = tiling.display(at: source) {
      // Leaving its own display: what the move preview showed there closes up too.
      var left = tiling.rows[source].current
      left.remove(windowID)
      placements += left.restingPlacements(on: display, gaps: tiling.gaps)
    }
    if let shown = self.arrival, shown.position != arrival.position {
      placements += tiling.restingPlacements(at: shown.position)
    }
    if let display = tiling.display(at: arrival.position) {
      placements += tiling.rows[arrival.position].current.arriving(windowID, at: arrival.index)
        .restingPlacements(on: display, gaps: tiling.gaps).filter { $0.id != windowID }
    }
    previewPlace = nil
    self.arrival = arrival
    return placements
  }

  /// Puts back the windows an arrival preview moved, on both displays; the dragged window stays
  /// under the pointer.
  package mutating func undoArrival(in tiling: TilingSnapshot) -> [Placement] {
    guard let arrival else { return [] }
    self.arrival = nil
    let positions = [arrival.position] + (tiling.onScreenPosition(of: windowID).map { [$0] } ?? [])
    return positions.flatMap(tiling.restingPlacements(at:)).filter { $0.id != windowID }
  }

  /// Keeps what the arrival preview shows: a drop there leaves the windows where they are.
  package mutating func forgetArrival() {
    arrival = nil
  }

  /// What a release at `location` does, the window being at `frame`: it joins another display if
  /// released over one; a resize makes the layout follow the window's last size; a move onto
  /// another window's slot puts it in there, the others making room. The layout must still be
  /// able to follow the drag.
  package func drop(at location: CGPoint, frame: CGRect?, in tiling: TilingSnapshot) -> DragDrop {
    if let arrival = arrival(at: location, in: tiling) { return .arrive(arrival) }
    guard let position = tiling.onScreenPosition(of: windowID), let frame,
      let slot = tiling.slot(of: windowID)
    else { return .back }
    // A grabbed window's resize was followed as it went; its frame may lag behind.
    if isResize && grab == nil && frame.hasOtherSize(than: slot.frame) {
      return .resize(position: position, frame: frame)
    }
    guard !isResize, let place = place(at: location, in: tiling) else { return .back }
    return .move(position: position, place: place)
  }
}

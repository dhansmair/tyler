import CoreGraphics

/// A tiled window the user is dragging, and what the preview shows of where it would go: there
/// is always exactly one open slot, the one the window would take. It decides; the caller moves
/// the windows and changes the lists.
package struct DragSession: Equatable, Sendable {
  package let windowID: WindowID
  /// Whether the window changed size, not only place. A resize never swaps.
  package var isResize = false
  /// Where a window dragged by its title bar or its edges was when the drag began.
  package let startFrame: CGRect?
  /// For a drag with the modifier, where it started; `nil` for a window dragged by its title bar
  /// or its edges.
  package var grab: ModifierGrab?
  /// The window shown in the dragged window's slot, the one a release would swap with.
  package private(set) var previewTarget: WindowID?
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

  /// Over the window's own display: the window a release at `location` would swap with moves
  /// into the dragged window's slot, and the one shown so far goes back to its own. Empty while
  /// the target stays the same.
  package mutating func previewSwap(
    at location: CGPoint, in tiling: TilingSnapshot
  ) -> [Placement] {
    guard let placements = tiling.currentPlacements(holding: windowID) else { return [] }
    let target = Workspace.dropTarget(for: windowID, at: location, among: placements)
    guard target != previewTarget else { return [] }
    var moves = placements.filter { $0.id == previewTarget }
    if let target, let slot = placements.first(where: { $0.id == windowID }) {
      moves.append(Placement(id: target, frame: slot.frame))
    }
    previewTarget = target
    return moves
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
      // Leaving its own display: the window it would have swapped with closes up too.
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
    previewTarget = nil
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

  /// Where the window the swap preview moved goes back to when the drag ends without a drop.
  package func previewTargetSlot(in tiling: TilingSnapshot) -> Placement? {
    previewTarget.flatMap(tiling.slot(of:))
  }

  /// Forgets the preview target without moving it, for a window that is gone.
  package mutating func forgetPreviewTarget(_ windowID: WindowID) {
    if previewTarget == windowID { previewTarget = nil }
  }

  /// What a release at `location` does, the window being at `frame`: it joins another display if
  /// released over one; a resize makes the layout follow the window's last size; a move onto
  /// another window's slot swaps the two. The layout must still be able to follow the drag.
  package func drop(at location: CGPoint, frame: CGRect?, in tiling: TilingSnapshot) -> DragDrop {
    if let arrival = arrival(at: location, in: tiling) { return .arrive(arrival) }
    guard let position = tiling.onScreenPosition(of: windowID),
      let placements = tiling.currentPlacements(holding: windowID), let frame,
      let slot = placements.first(where: { $0.id == windowID })
    else { return .back }
    // A grabbed window's resize was followed as it went; its frame may lag behind.
    if isResize && grab == nil && frame.hasOtherSize(than: slot.frame) {
      return .resize(position: position, frame: frame)
    }
    guard !isResize,
      let target = Workspace.dropTarget(for: windowID, at: location, among: placements)
    else { return .back }
    return .swap(position: position, target: target)
  }
}

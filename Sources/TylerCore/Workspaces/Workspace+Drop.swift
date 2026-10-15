import CoreGraphics

/// Dropping a dragged window: it goes in at the slot under the pointer, on its own display or
/// another, and the others make room. In `tall`, that is within the section under the pointer.
extension Workspace {
  /// Where `windowID` is in the list now.
  package func place(of windowID: WindowID) -> ListPlace? {
    windows.firstIndex(of: windowID).map { index in
      ListPlace(index: index, isInMainSection: layout == .tall && index < mainSectionCount)
    }
  }

  /// Where `windowID` goes in if it is dropped at `point`: the place whose slot, with the window
  /// moved there, is under the point. Its own place is tried first, so over its own slot (in
  /// `full`, that is everywhere) nothing changes. `nil` in a gap, outside the tiled area, or for
  /// a window that isn't here.
  package func dropPlace(
    for windowID: WindowID, at point: CGPoint, on display: DisplayInfo, gaps: LayoutGaps
  ) -> ListPlace? {
    movePlaces(of: windowID).first { place in
      moving(windowID, to: place).placements(on: display, gaps: gaps).contains {
        $0.id == windowID && $0.frame.contains(point)
      }
    }
  }

  /// This workspace with `windowID` moved to `place`.
  package func moving(_ windowID: WindowID, to place: ListPlace) -> Workspace {
    var copy = self
    copy.move(windowID, to: place)
    return copy
  }

  /// Moves `windowID` to `place`; the windows between its old and new place shift by one, and in
  /// `tall` the master section grows or shrinks if it changes section. Returns false if it isn't
  /// here or is there already.
  @discardableResult
  package mutating func move(_ windowID: WindowID, to place: ListPlace) -> Bool {
    guard let own = self.place(of: windowID), windows.indices.contains(place.index) else {
      return false
    }
    let joinsMainSection = layout == .tall && place.isInMainSection
    guard own.index != place.index || own.isInMainSection != joinsMainSection else {
      return false
    }
    let count = count
    moveWindow(at: own.index, to: place.index)
    if own.isInMainSection != joinsMainSection {
      update(\.tall) { state, _ in
        if joinsMainSection {
          state.growMainSection(of: count)
        } else {
          state.shrinkMainSection(of: count)
        }
      }
    }
    return true
  }

  /// Where `windowID`, coming from another workspace, goes in if it is dropped at `point`: the
  /// place whose slot, with the window in it there, is under the point. So the slot a preview
  /// leaves open (see `arriving(_:at:)`) is always the one under the pointer. `nil` in a gap or
  /// outside the tiled area.
  package func arrivalPlace(
    of windowID: WindowID, at point: CGPoint, on display: DisplayInfo, gaps: LayoutGaps
  ) -> ListPlace? {
    arrivalPlaces.first { place in
      arriving(windowID, at: place).placements(on: display, gaps: gaps).contains {
        $0.id == windowID && $0.frame.contains(point)
      }
    }
  }

  /// This workspace with `windowID` gone in at `place`.
  package func arriving(_ windowID: WindowID, at place: ListPlace) -> Workspace {
    var copy = self
    copy.arrive(windowID, at: place)
    return copy
  }

  /// Adds `windowID` at `place` (the window there and those after it move one later), or last if
  /// the place is past the end. In `tall`, a window that arrives in the master section makes it
  /// one larger. Returns false if the window is here already.
  @discardableResult
  package mutating func arrive(_ windowID: WindowID, at place: ListPlace) -> Bool {
    let count = count
    let target = windows.indices.contains(place.index) ? windows[place.index] : nil
    guard insert(windowID, before: target) else { return false }
    if layout == .tall && place.isInMainSection {
      update(\.tall) { state, _ in state.growMainSection(of: count) }
    }
    return true
  }

  /// The places a window arriving can go in at; in `tall`, those in the stack first, as for
  /// `movePlaces(of:)`.
  private var arrivalPlaces: [ListPlace] {
    guard layout == .tall else { return (0...count).map { ListPlace(index: $0) } }
    let mains = mainSectionCount
    return (mains...count).map { ListPlace(index: $0, isInMainSection: false) }
      + (0...mains).map { ListPlace(index: $0, isInMainSection: true) }
  }

  /// The places `windowID` can be moved to: its own first, so it stays put over its own slot,
  /// then those in the other section of `tall`, which has the other column to itself, then the
  /// rest. With every window in `tall`'s master section there is one column; its places in a new
  /// stack must come before those in the master section, which cover the whole width.
  private func movePlaces(of windowID: WindowID) -> [ListPlace] {
    guard let own = place(of: windowID) else { return [] }
    guard layout == .tall else {
      return [own] + windows.indices.filter { $0 != own.index }.map { ListPlace(index: $0) }
    }
    let otherMains = mainSectionCount - (own.isInMainSection ? 1 : 0)
    let mains = (0...otherMains).map { ListPlace(index: $0, isInMainSection: true) }
    let stack = (otherMains..<count).map { ListPlace(index: $0, isInMainSection: false) }
    let (same, other) = own.isInMainSection ? (mains, stack) : (stack, mains)
    return [own] + other + same.filter { $0 != own }
  }
}

import CoreGraphics

/// Dropping a dragged window on its own display: it goes in at the slot under the pointer, and
/// the others make room.
extension Workspace {
  /// Where `windowID` is in the list now.
  package func place(of windowID: WindowID) -> ListPlace? {
    windows.firstIndex(of: windowID).map(ListPlace.init(index:))
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

  /// Moves `windowID` to `place`; the windows between its old and new place shift by one.
  /// Returns false if it isn't here or is there already.
  @discardableResult
  package mutating func move(_ windowID: WindowID, to place: ListPlace) -> Bool {
    guard let index = windows.firstIndex(of: windowID), windows.indices.contains(place.index),
      index != place.index
    else { return false }
    moveWindow(at: index, to: place.index)
    return true
  }

  /// The places `windowID` can be moved to, its own first.
  private func movePlaces(of windowID: WindowID) -> [ListPlace] {
    guard let own = place(of: windowID) else { return [] }
    return [own] + windows.indices.filter { $0 != own.index }.map(ListPlace.init(index:))
  }
}

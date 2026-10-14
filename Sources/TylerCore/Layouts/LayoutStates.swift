/// Holds every layout's state, not only the active one's, so a layout's state survives switching
/// away and back.
package struct LayoutStates: Codable, Equatable, Sendable {
  package var tall: TallLayoutState
  package var grid: GridLayoutState
  package var full: FullLayoutState
  package var strip: StripLayoutState

  package init(
    tall: TallLayoutState = .init(), grid: GridLayoutState = .init(),
    full: FullLayoutState = .init(), strip: StripLayoutState = .init()
  ) {
    self.tall = tall
    self.grid = grid
    self.full = full
    self.strip = strip
  }

  /// A layout missing from the file, as in one written before that layout existed, gets a new
  /// workspace's state.
  package init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    tall = try container.decodeIfPresent(TallLayoutState.self, forKey: .tall) ?? .init()
    grid = try container.decodeIfPresent(GridLayoutState.self, forKey: .grid) ?? .init()
    full = try container.decodeIfPresent(FullLayoutState.self, forKey: .full) ?? .init()
    strip = try container.decodeIfPresent(StripLayoutState.self, forKey: .strip) ?? .init()
  }

  /// `windows` is the list the window leaves, still holding it.
  mutating func remove(_ windowID: WindowID, from windows: [WindowID]) {
    tall.remove(windowID, from: windows)
    grid.remove(windowID, from: windows)
    full.remove(windowID, from: windows)
    strip.remove(windowID, from: windows)
  }

  mutating func adopt(_ windowID: WindowID, from other: LayoutStates) {
    tall.adopt(windowID, from: other.tall)
    grid.adopt(windowID, from: other.grid)
    full.adopt(windowID, from: other.full)
    strip.adopt(windowID, from: other.strip)
  }
}

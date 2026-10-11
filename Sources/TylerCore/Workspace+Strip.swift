import CoreGraphics

/// The strip layout's state on a workspace: window sizes, and the view of the strip.
extension Workspace {
  // MARK: - Window sizes

  /// The window's size in the strip layout.
  public func size(of windowID: WindowID) -> WindowSize {
    sizes[windowID] ?? .half
  }

  /// What `setSizeWithPartner` did.
  public enum SizeChange: Equatable, Sendable {
    case changed
    /// The window already had that size.
    case unchanged
    /// A `quarter` window needs a neighbour to share its column with, and neither is free.
    case noPartner
  }

  /// Sets a tiled window's strip size the way a user means it. Making it `quarter` makes a
  /// neighbour `quarter` too, so the two share a column: the next window, or the previous one if
  /// the next already shares a column (or there is none). Changing a `quarter` window to another
  /// size puts its column mate back to `half`.
  @discardableResult
  public mutating func setSizeWithPartner(
    _ size: WindowSize, of windowID: WindowID
  ) -> SizeChange {
    guard let index = windows.firstIndex(of: windowID) else { return .unchanged }
    guard self.size(of: windowID) != size else { return .unchanged }
    if size == .quarter {
      let isFree = { (index: Int) in
        self.windows.indices.contains(index) && self.size(of: self.windows[index]) != .quarter
      }
      guard let partner = [index + 1, index - 1].first(where: isFree) else { return .noPartner }
      sizes[windows[partner]] = .quarter
    } else {
      unpair(windowID)
    }
    sizes[windowID] = size
    refitView()
    return .changed
  }

  /// Puts the column mate of a `quarter` window back to `half`, so it doesn't stay a lone quarter.
  mutating func unpair(_ windowID: WindowID) {
    guard size(of: windowID) == .quarter, let index = windows.firstIndex(of: windowID) else {
      return
    }
    let columns = StripColumns(sizes: windows.map(size(of:)))
    guard let column = columns.column(of: index) else { return }
    for mate in columns.columns[column] where mate != index {
      sizes[windows[mate]] = nil
    }
  }

  /// Sets a tiled window's size in the strip layout, and nothing else (restoring a saved state
  /// sets each window's size this way). Returns whether it changed.
  @discardableResult
  public mutating func setSize(_ size: WindowSize, of windowID: WindowID) -> Bool {
    guard contains(windowID), self.size(of: windowID) != size else { return false }
    sizes[windowID] = size
    refitView()
    return true
  }

  // MARK: - The strip's view

  /// One place the strip's view can rest, where a swipe can settle.
  public struct StripView: Equatable, Sendable {
    /// How far the strip is scrolled from its left end, in points.
    public let offset: CGFloat
    /// The first window of the leftmost visible column, for `scroll(toFirstVisible:)`.
    public let firstVisible: WindowID
    /// Every window's frame with this view, as `arrangement(in:gaps:)` gives them.
    public let arrangement: [Placement]
  }

  /// Every view the strip can rest at, left to right; none in other layouts.
  public func stripViews(in area: CGRect, gaps: LayoutGaps) -> [StripView] {
    guard layout == .strip else { return [] }
    let columns = StripColumns(sizes: windows.map(size(of:)))
    let geometry = StripGeometry(area: area, gaps: gaps)
    return columns.starts.map { start in
      let first = columns.columns[start][0]
      var input = layoutInput
      input.firstVisible = first
      let frames = StripLayout().frames(for: input, in: area, gaps: gaps)
      return StripView(
        offset: CGFloat(geometry.left(at: columns.offset(of: start)) - geometry.left(at: 0)),
        firstVisible: windows[first],
        arrangement: zip(windows, frames).map { Placement(id: $0, frame: $1) })
    }
  }

  /// Scrolls the strip so that `windowID`'s column is the leftmost in view, or as near as the
  /// strip's end allows. If the focused window scrolled out of view, focus moves to the nearest
  /// window in view. Returns whether focus moved.
  @discardableResult
  public mutating func scroll(toFirstVisible windowID: WindowID) -> Bool {
    let columns = StripColumns(sizes: windows.map(size(of:)))
    guard let column = windows.firstIndex(of: windowID).flatMap(columns.column(of:)) else {
      return false
    }
    let start = columns.clampedToEnd(column)
    firstVisible = windows[columns.columns[start][0]]
    let visible = columns.visible(from: start)
    guard let focusedColumn = focusedIndex.flatMap(columns.column(of:)),
      !visible.contains(focusedColumn)
    else { return false }
    let nearest = focusedColumn < visible.lowerBound ? visible.lowerBound : visible.upperBound - 1
    focused = windows[columns.columns[nearest][0]]
    return true
  }

  /// Moves the strip's view the least that shows the focused window whole.
  mutating func refitView() {
    guard !windows.isEmpty else {
      firstVisible = nil
      return
    }
    let columns = StripColumns(sizes: windows.map(size(of:)))
    let previous = firstVisible.flatMap(windows.firstIndex(of:)).flatMap(columns.column(of:)) ?? 0
    let start = columns.fittedStart(
      previous: previous, focused: focusedIndex.flatMap(columns.column(of:)))
    firstVisible = windows[columns.columns[start][0]]
  }
}

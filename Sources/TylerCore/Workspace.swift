import CoreGraphics

/// Where a window should go.
public struct Placement: Equatable, Sendable {
  public let id: WindowID
  public let frame: CGRect

  public init(id: WindowID, frame: CGRect) {
    self.id = id
    self.frame = frame
  }
}

/// An ordered list of tiled windows, xmonad style: the first window is the master, every window
/// has a clear next and previous (wrapping around), and the layout turns list order into frames.
public struct Workspace: Equatable, Sendable {
  public private(set) var windows: [WindowID] = []
  /// The tiled window that `focus` and `swap` are relative to.
  public private(set) var focused: WindowID?
  public var layout: LayoutKind
  public private(set) var parameters: LayoutParameters
  /// Window sizes for the strip layout, kept in every layout. Windows without one are `half`.
  public private(set) var sizes: [WindowID: WindowSize] = [:]
  /// A window in the strip's leftmost visible column; `nil` while the workspace is empty. Kept
  /// in every layout, always showing the focused window, so the strip starts out sensibly.
  public private(set) var firstVisible: WindowID?

  public init(layout: LayoutKind = .tall, parameters: LayoutParameters = LayoutParameters()) {
    self.layout = layout
    self.parameters = parameters
  }

  public var count: Int { windows.count }

  public func contains(_ windowID: WindowID) -> Bool {
    windows.contains(windowID)
  }

  /// The 1-based position in the list; 1 is the master.
  public func slot(of windowID: WindowID) -> Int? {
    windows.firstIndex(of: windowID).map { $0 + 1 }
  }

  // MARK: - Membership

  /// Adds a window right after the focused one, or at the end if nothing is focused.
  @discardableResult
  public mutating func insert(_ windowID: WindowID) -> Bool {
    guard !contains(windowID) else { return false }
    windows.insert(windowID, at: insertionIndex)
    refitView()
    return true
  }

  /// Adds a window at the end of the list, whatever has focus.
  @discardableResult
  public mutating func append(_ windowID: WindowID) -> Bool {
    guard !contains(windowID) else { return false }
    windows.append(windowID)
    refitView()
    return true
  }

  /// Removes a window. If it had focus, focus moves to the window that took its place (or the
  /// new last window), and so does the strip's view if it started at that window.
  @discardableResult
  public mutating func remove(_ windowID: WindowID) -> Bool {
    guard let index = windows.firstIndex(of: windowID) else { return false }
    windows.remove(at: index)
    sizes[windowID] = nil
    let successor = windows.isEmpty ? nil : windows[min(index, windows.count - 1)]
    if focused == windowID { focused = successor }
    if firstVisible == windowID { firstVisible = successor }
    refitView()
    return true
  }

  /// Makes `eligible` exactly the set of tiled windows. Windows no longer eligible are dropped,
  /// the others keep their order, and new ones are inserted as a block after the focused window
  /// in the order given. Returns whether anything changed.
  @discardableResult
  public mutating func sync(eligible: [WindowID]) -> Bool {
    let wanted = Set(eligible)
    var changed = false
    for windowID in windows where !wanted.contains(windowID) {
      remove(windowID)
      changed = true
    }
    var insertionPoint = insertionIndex
    for windowID in eligible where !contains(windowID) {
      windows.insert(windowID, at: insertionPoint)
      insertionPoint += 1
      changed = true
    }
    refitView()
    return changed
  }

  // MARK: - Focus and order

  /// Records that the operating system focused `windowID`. Windows that aren't tiled are
  /// ignored, so `focus next` stays relative to the last tiled window you used.
  @discardableResult
  public mutating func setFocus(_ windowID: WindowID) -> Bool {
    guard contains(windowID), focused != windowID else { return false }
    focused = windowID
    refitView()
    return true
  }

  /// Moves focus within the list, wrapping around. With nothing focused, `next` and `master`
  /// pick the first window and `prev` the last. Returns the newly focused window.
  @discardableResult
  public mutating func focus(_ target: ListTarget) -> WindowID? {
    guard !windows.isEmpty else { return nil }
    let index: Int
    switch target {
    case .main:
      index = 0
    case .next:
      index = focusedIndex.map { $0.stepped(by: 1, wrappingAt: windows.count) } ?? 0
    case .prev:
      index =
        focusedIndex.map { $0.stepped(by: -1, wrappingAt: windows.count) } ?? windows.count - 1
    }
    focused = windows[index]
    refitView()
    return focused
  }

  /// Swaps the focused window with its neighbour (wrapping) or with the master. If the focused
  /// window already is the master, `master` swaps it with the second window. The focused window
  /// keeps focus and moves with it. Returns false if there is nothing to swap.
  @discardableResult
  public mutating func swap(_ target: ListTarget) -> Bool {
    guard windows.count >= 2, let current = focusedIndex else { return false }
    let other: Int
    switch target {
    case .next: other = (current + 1) % windows.count
    case .prev: other = (current - 1 + windows.count) % windows.count
    case .main: other = current == 0 ? 1 : 0
    }
    windows.swapAt(current, other)
    refitView()
    return true
  }

  /// Swaps two windows' slots, whatever has focus; focus stays on the window it was on. Returns
  /// false if either window isn't in the list or they are the same window.
  @discardableResult
  public mutating func swap(_ first: WindowID, with second: WindowID) -> Bool {
    guard first != second, let firstIndex = windows.firstIndex(of: first),
      let secondIndex = windows.firstIndex(of: second)
    else { return false }
    windows.swapAt(firstIndex, secondIndex)
    refitView()
    return true
  }

  /// The window that `windowID` would swap with if it were dropped at `point`: the one whose
  /// slot is under the point. Nothing while the point is still in `windowID`'s own slot (in
  /// `full`, that is everywhere), in a gap, or outside the tiled area.
  public func dropTarget(
    for windowID: WindowID, at point: CGPoint, in area: CGRect, gaps: LayoutGaps
  ) -> WindowID? {
    Self.dropTarget(for: windowID, at: point, among: placements(in: area, gaps: gaps))
  }

  /// `dropTarget(for:at:in:gaps:)` for placements already worked out, so a caller that needs them
  /// anyway lays the workspace out once.
  public static func dropTarget(
    for windowID: WindowID, at point: CGPoint, among placements: [Placement]
  ) -> WindowID? {
    guard let own = placements.first(where: { $0.id == windowID }), !own.frame.contains(point)
    else { return nil }
    return placements.first { $0.id != windowID && $0.frame.contains(point) }?.id
  }

  // MARK: - Layout

  /// The window's size in the strip layout.
  public func size(of windowID: WindowID) -> WindowSize {
    sizes[windowID] ?? .half
  }

  /// Sets a tiled window's size in the strip layout. Returns whether it changed.
  @discardableResult
  public mutating func setSize(_ size: WindowSize, of windowID: WindowID) -> Bool {
    guard contains(windowID), self.size(of: windowID) != size else { return false }
    sizes[windowID] = size
    refitView()
    return true
  }

  @discardableResult
  public mutating func adjustRatio(by delta: Double) -> Bool {
    parameters.adjustRatio(by: delta)
  }

  /// Follows the user resizing `windowID` to `frame`: the layout moves the dividers whose edges
  /// were dragged. Returns whether the parameters changed.
  @discardableResult
  public mutating func resize(
    _ windowID: WindowID, to frame: CGRect, in area: CGRect, gaps: LayoutGaps
  ) -> Bool {
    guard let index = windows.firstIndex(of: windowID),
      let updated = layout.implementation.parameters(
        afterResizing: index, to: frame, input: layoutInput, in: area, gaps: gaps),
      updated != parameters
    else { return false }
    parameters = updated
    return true
  }

  public mutating func cycleLayout() {
    layout = layout.next
  }

  /// Every window's frame, in list order. In the strip layout, windows out of view get frames
  /// off the area.
  public func arrangement(in area: CGRect, gaps: LayoutGaps) -> [Placement] {
    let frames = layout.implementation.frames(for: layoutInput, in: area, gaps: gaps)
    return zip(windows, frames).map { Placement(id: $0, frame: $1) }
  }

  /// The windows in view and where they go, in list order. That is every window, except in the
  /// strip layout.
  public func placements(in area: CGRect, gaps: LayoutGaps) -> [Placement] {
    arrangement(in: area, gaps: gaps).filter { area.shows($0.frame) }
  }

  /// The windows out of view: only in the strip layout.
  public func offView(in area: CGRect, gaps: LayoutGaps) -> [WindowID] {
    arrangement(in: area, gaps: gaps).filter { !area.shows($0.frame) }.map(\.id)
  }

  /// Where every window rests on `display`: the windows in view in their slots, the others
  /// parked at the display's edge, keeping the size they'll have in view.
  public func restingPlacements(on display: DisplayInfo, gaps: LayoutGaps) -> [Placement] {
    let area = display.visibleFrame
    return arrangement(in: area, gaps: gaps).map { placement in
      area.shows(placement.frame)
        ? placement
        : Placement(id: placement.id, frame: Parking.frame(for: placement.frame, on: display))
    }
  }

  private var layoutInput: LayoutInput {
    LayoutInput(
      count: windows.count, parameters: parameters, sizes: windows.map(size(of:)),
      firstVisible: firstVisible.flatMap(windows.firstIndex(of:)) ?? 0)
  }

  // MARK: - The strip's view

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
  private mutating func refitView() {
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

  private var focusedIndex: Int? {
    focused.flatMap { windows.firstIndex(of: $0) }
  }

  /// Where a window joining the list goes: right after the focused one, or at the end.
  private var insertionIndex: Int {
    focusedIndex.map { $0 + 1 } ?? windows.count
  }
}

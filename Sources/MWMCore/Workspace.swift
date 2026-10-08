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
    windows.insert(windowID, at: focusedIndex.map { $0 + 1 } ?? windows.count)
    return true
  }

  /// Removes a window. If it had focus, focus moves to the window that took its place (or the
  /// new last window).
  @discardableResult
  public mutating func remove(_ windowID: WindowID) -> Bool {
    guard let index = windows.firstIndex(of: windowID) else { return false }
    windows.remove(at: index)
    if focused == windowID {
      focused = windows.isEmpty ? nil : windows[min(index, windows.count - 1)]
    }
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
    var insertionPoint = focusedIndex.map { $0 + 1 } ?? windows.count
    for windowID in eligible where !contains(windowID) {
      windows.insert(windowID, at: insertionPoint)
      insertionPoint += 1
      changed = true
    }
    return changed
  }

  // MARK: - Focus and order

  /// Records that the operating system focused `windowID`. Windows that aren't tiled are
  /// ignored, so `focus next` stays relative to the last tiled window you used.
  @discardableResult
  public mutating func setFocus(_ windowID: WindowID) -> Bool {
    guard contains(windowID), focused != windowID else { return false }
    focused = windowID
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
      index = focusedIndex.map { ($0 + 1) % windows.count } ?? 0
    case .prev:
      index = focusedIndex.map { ($0 - 1 + windows.count) % windows.count } ?? windows.count - 1
    }
    focused = windows[index]
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
    return true
  }

  // MARK: - Layout

  @discardableResult
  public mutating func adjustRatio(by delta: Double) -> Bool {
    parameters.adjustRatio(by: delta)
  }

  public mutating func cycleLayout() {
    layout = layout.next
  }

  /// One placement per window, in list order.
  public func placements(in area: CGRect) -> [Placement] {
    let frames = layout.layout.frames(count: windows.count, in: area, parameters: parameters)
    return zip(windows, frames).map { Placement(id: $0, frame: $1) }
  }

  private var focusedIndex: Int? {
    focused.flatMap { windows.firstIndex(of: $0) }
  }
}

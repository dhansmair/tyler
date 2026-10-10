/// The virtual monitors of one display, stacked vertically like pages. Each monitor is its own
/// `Workspace`; exactly one is current (on screen) and the others are parked. A window belongs
/// to at most one monitor.
public struct MonitorStack: Equatable, Sendable {
  /// How many monitors a stack has until the config file makes it configurable (M6).
  public static let defaultCount = 4

  public private(set) var monitors: [Workspace]
  /// 0-based index of the monitor on screen.
  public private(set) var currentIndex = 0

  /// A stack of `count` empty monitors (at least one), starting on the first.
  public init(count: Int = MonitorStack.defaultCount) {
    monitors = Array(repeating: Workspace(), count: max(1, count))
  }

  public var count: Int { monitors.count }
  public var indices: Range<Int> { monitors.indices }

  public subscript(index: Int) -> Workspace {
    get { monitors[index] }
    set { monitors[index] = newValue }
  }

  /// The monitor on screen.
  public var current: Workspace {
    get { monitors[currentIndex] }
    set { monitors[currentIndex] = newValue }
  }

  /// The index of the monitor holding `windowID`, if any.
  public func monitor(of windowID: WindowID) -> Int? {
    monitors.firstIndex { $0.contains(windowID) }
  }

  /// Every window on any monitor.
  public var allWindows: Set<WindowID> {
    Set(monitors.flatMap(\.windows))
  }

  /// Resolves a target to an index: `up` and `down` wrap around, numbers are 1-based and `nil`
  /// when out of range.
  public func index(of target: MonitorTarget) -> Int? {
    switch target {
    case .up: (currentIndex - 1 + count) % count
    case .down: (currentIndex + 1) % count
    case .number(let number): (1...count).contains(number) ? number - 1 : nil
    }
  }

  /// Makes the monitor at `index` current. Returns false if it is out of range.
  @discardableResult
  public mutating func select(_ index: Int) -> Bool {
    guard indices.contains(index) else { return false }
    currentIndex = index
    return true
  }

  /// Moves a window from its monitor to the one at `index`, where it is inserted after the
  /// focused window and becomes focused. Returns false if the window is on no monitor, already
  /// on that one, or the index is out of range.
  @discardableResult
  public mutating func move(_ windowID: WindowID, to index: Int) -> Bool {
    guard indices.contains(index), let source = monitor(of: windowID), source != index else {
      return false
    }
    monitors[source].remove(windowID)
    monitors[index].insert(windowID)
    monitors[index].setFocus(windowID)
    return true
  }

  /// Records that `windowID` got focus, on whichever monitor holds it.
  @discardableResult
  public mutating func setFocus(_ windowID: WindowID) -> Bool {
    guard let index = monitor(of: windowID) else { return false }
    return monitors[index].setFocus(windowID)
  }
}

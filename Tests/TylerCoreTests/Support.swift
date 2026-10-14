import CoreGraphics

@testable import TylerCore

/// Window ids from plain numbers.
func ids(_ values: UInt32...) -> [WindowID] { values.map(WindowID.init) }

/// A workspace holding `values` in order, with `focus` focused if given.
func makeWorkspace(_ values: UInt32..., focus: UInt32? = nil) -> Workspace {
  var workspace = Workspace()
  for value in values { workspace.insert(WindowID(value)) }
  if let focus { workspace.setFocus(WindowID(focus)) }
  return workspace
}

/// Windows 1 to `count`.
func windowIDs(count: Int) -> [WindowID] {
  (0..<count).map { WindowID(UInt32($0 + 1)) }
}

extension Layout {
  /// The frames for windows 1 to `count`, as most tests ask for them.
  func frames(
    count: Int, in area: CGRect, state: State = State(), gaps: LayoutGaps = LayoutGaps()
  ) -> [CGRect] {
    frames(of: windowIDs(count: count), state: state, in: area, gaps: gaps)
  }

  /// `state(after:of:state:in:gaps:)` for windows 1 to `count`.
  func state(
    afterResizing index: Int, to frame: CGRect, count: Int, in area: CGRect,
    state: State = State(), gaps: LayoutGaps = LayoutGaps()
  ) -> State? {
    self.state(
      after: ResizedWindow(index: index, frame: frame), of: windowIDs(count: count),
      state: state, in: area, gaps: gaps)
  }
}

extension Workspace {
  func size(of windowID: WindowID) -> WindowSize {
    layoutStates.strip.size(of: windowID)
  }

  @discardableResult
  mutating func setSize(_ size: WindowSize, of windowID: WindowID) -> Bool {
    guard contains(windowID) else { return false }
    return update(\.strip) { strip, _ in strip.setSize(size, of: windowID) }
  }

  @discardableResult
  mutating func setSizeWithPartner(
    _ size: WindowSize, of windowID: WindowID
  ) -> StripLayoutState.SizeChange {
    update(\.strip) { strip, windows in strip.setSizeWithPartner(size, of: windowID, in: windows) }
  }

  @discardableResult
  mutating func adjustRatio(by delta: Double) -> Bool {
    update(\.tall) { tall, _ in tall.adjustRatio(by: delta) }
  }
}

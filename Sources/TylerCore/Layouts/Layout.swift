import CoreGraphics

/// Turns a workspace's windows into one frame each, in list order. Adding a layout means a
/// conforming type with its `State`, a field for it in `LayoutStates`, and a `LayoutKind` case;
/// the compiler then asks for the case's `bound` and `symbol`.
package protocol Layout: Sendable {
  associatedtype State: LayoutState

  func frames(
    of windows: [WindowID], state: State, in area: CGRect, gaps: LayoutGaps
  ) -> [CGRect]

  /// The state that puts the resized window's edges where the user dragged them, or `nil` if the
  /// layout doesn't follow: no edge it can move was moved. The other edges snap back.
  func state(
    after resize: ResizedWindow, of windows: [WindowID], state: State, in area: CGRect,
    gaps: LayoutGaps
  ) -> State?
}

extension Layout {
  package func state(
    after resize: ResizedWindow, of windows: [WindowID], state: State, in area: CGRect,
    gaps: LayoutGaps
  ) -> State? {
    nil
  }
}

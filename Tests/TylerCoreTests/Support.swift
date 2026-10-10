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

extension Layout {
  /// The frames for `count` windows, as most tests ask for them.
  func frames(
    count: Int, in area: CGRect, parameters: LayoutParameters = LayoutParameters(),
    gaps: LayoutGaps = LayoutGaps()
  ) -> [CGRect] {
    frames(for: LayoutInput(count: count, parameters: parameters), in: area, gaps: gaps)
  }

  /// `parameters(afterResizing:to:input:in:gaps:)` for `count` windows.
  func parameters(
    afterResizing index: Int, to frame: CGRect, count: Int, in area: CGRect,
    parameters: LayoutParameters, gaps: LayoutGaps = LayoutGaps()
  ) -> LayoutParameters? {
    self.parameters(
      afterResizing: index, to: frame, input: LayoutInput(count: count, parameters: parameters),
      in: area, gaps: gaps)
  }
}

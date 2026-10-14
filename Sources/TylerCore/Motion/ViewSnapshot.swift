import CoreGraphics

/// A workspace's view before a change, and every window's frame with it, so the change can be
/// animated as a scroll.
package struct ViewSnapshot: Equatable, Sendable {
  package let display: DisplayInfo
  package let gaps: LayoutGaps
  package let view: WindowID?
  package let arrangement: [Placement]

  package init(_ workspace: Workspace, on display: DisplayInfo, gaps: LayoutGaps) {
    self.display = display
    self.gaps = gaps
    view = workspace.firstVisible
    arrangement = workspace.arrangement(in: display.visibleFrame, gaps: gaps)
  }

  /// `nil` if the view didn't move, or the layout doesn't scroll.
  package func scroll(to workspace: Workspace) -> Transition? {
    guard workspace.scrolls, workspace.firstVisible != view else { return nil }
    return ScrollPlan(
      from: arrangement, to: workspace.arrangement(in: display.visibleFrame, gaps: gaps),
      on: display
    ).transition
  }
}

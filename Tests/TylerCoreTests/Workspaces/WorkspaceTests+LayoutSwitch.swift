import CoreGraphics
import Testing

@testable import TylerCore

@Suite("Workspace: switching layouts")
struct WorkspaceLayoutSwitchTests {
  /// Going through every other layout and back brings back the same frames: each layout's state
  /// (tall's ratio and rows, the grid's sizes, the strip's sizes and view) outlives a switch.
  @Test(arguments: LayoutKind.allCases)
  func aLayoutKeepsItsStateThroughTheOthers(kind: LayoutKind) {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    var workspace = Workspace(
      layout: kind,
      layoutStates: LayoutStates(
        tall: TallLayoutState(mainRatio: 0.7, rowWeights: [[], [1, 3]]),
        grid: GridLayoutState(weights: ColumnWeights(columns: [2, 1], rows: [[1, 3]]))))
    for raw in [1, 2, 3, 4, 5] as [UInt32] { workspace.append(WindowID(raw)) }
    workspace.setSize(.full, of: WindowID(2))
    workspace.setFocus(WindowID(5))
    let before = workspace.arrangement(in: area, gaps: LayoutGaps())
    for _ in LayoutKind.allCases { workspace.cycleLayout(through: LayoutKind.allCases) }
    #expect(workspace.layout == kind)
    #expect(workspace.arrangement(in: area, gaps: LayoutGaps()) == before)
  }
}

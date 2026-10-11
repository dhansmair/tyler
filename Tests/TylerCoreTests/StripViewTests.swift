import CoreGraphics
import Testing

@testable import TylerCore

/// The strip's view on a workspace: four half windows in 1000 × 600 show two at a time.
@Suite("Strip layout: the view")
struct StripViewTests {
  private static let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
  private let display = DisplayInfo(id: 1, frame: Self.area, visibleFrame: Self.area)
  private let gaps = LayoutGaps()

  private func strip(_ values: UInt32..., focus: UInt32) -> Workspace {
    var workspace = Workspace(layout: .strip)
    for value in values { workspace.append(WindowID(value)) }
    workspace.setFocus(WindowID(focus))
    return workspace
  }

  private func visible(_ workspace: Workspace) -> [WindowID] {
    workspace.placements(in: Self.area, gaps: gaps).map(\.id)
  }

  @Test(arguments: [
    (UInt32(1), [UInt32(1), 2]),
    (UInt32(2), [UInt32(1), 2]),
    (UInt32(3), [UInt32(2), 3]),
    (UInt32(4), [UInt32(3), 4]),
  ])
  func focusingAWindowFromTheLeftScrollsJustEnough(focus: UInt32, shown: [UInt32]) {
    var workspace = strip(1, 2, 3, 4, focus: 1)
    for value in 1...focus { workspace.setFocus(WindowID(value)) }
    #expect(visible(workspace) == shown.map(WindowID.init))
    #expect(workspace.offView(in: Self.area, gaps: gaps).count == 2)
  }

  @Test func focusingAWindowLeftOfTheViewMakesItTheFirst() {
    var workspace = strip(1, 2, 3, 4, focus: 4)
    workspace.focus(.main)
    #expect(visible(workspace) == ids(1, 2))
    workspace.focus(.prev)
    #expect(visible(workspace) == ids(3, 4), "wrapping round to the last window")
  }

  @Test func removingTheFirstVisibleWindowKeepsTheViewFull() {
    var workspace = strip(1, 2, 3, 4, focus: 4)
    workspace.remove(WindowID(3))
    #expect(visible(workspace) == ids(2, 4))
  }

  @Test func aWindowGrowingToFullShowsAlone() {
    var workspace = strip(1, 2, 3, focus: 2)
    workspace.setSize(.full, of: WindowID(2))
    #expect(visible(workspace) == ids(2))
  }

  @Test func scrollingMovesFocusIntoTheView() {
    var workspace = strip(1, 2, 3, 4, focus: 1)
    let moved = workspace.scroll(toFirstVisible: WindowID(3))
    #expect(moved)
    #expect(workspace.focused == WindowID(3), "the nearest window in view")
    #expect(visible(workspace) == ids(3, 4))
  }

  @Test func scrollingStopsAtTheEnd() {
    var workspace = strip(1, 2, 3, 4, focus: 4)
    let moved = workspace.scroll(toFirstVisible: WindowID(4))
    #expect(!moved, "the focused window stays in view")
    #expect(visible(workspace) == ids(3, 4))
  }

  @Test func windowsOutOfViewRestParked() {
    let workspace = strip(1, 2, 3, 4, focus: 1)
    let resting = workspace.restingPlacements(on: display, gaps: gaps)
    #expect(resting[1].frame == CGRect(x: 500, y: 0, width: 500, height: 600))
    #expect(resting[2].frame == CGRect(x: 999, y: 0, width: 500, height: 600))
    #expect(resting[3].frame == CGRect(x: 999, y: 0, width: 500, height: 600))
  }

  @Test func otherLayoutsShowEveryWindow() {
    var workspace = strip(1, 2, 3, 4, focus: 4)
    workspace.layout = .tall
    #expect(visible(workspace) == ids(1, 2, 3, 4))
    #expect(workspace.offView(in: Self.area, gaps: gaps).isEmpty)
    #expect(
      workspace.restingPlacements(on: display, gaps: gaps)
        == workspace.placements(in: Self.area, gaps: gaps))
  }

  @Test func theViewSurvivesARestart() {
    var row = WorkspaceRow()
    var workspace = strip(1, 2, 3, 4, focus: 1)
    workspace.setSize(.full, of: WindowID(2))
    workspace.setSize(.quarter, of: WindowID(3))
    workspace.scroll(toFirstVisible: WindowID(3))
    row[0] = workspace
    let saved = SavedState(row: row, floated: [], tilingEnabled: true, originalFrames: [:])
    #expect(saved.row(count: 4) { _ in true } == row)
  }

  @Test func aFileFromBeforeTheStripGivesHalfWindows() {
    let saved = SavedState.SavedWorkspace(
      windows: ids(1, 2), focused: WindowID(2), layout: .tall, mainRatio: 0.5)
    let workspace = saved.workspace { _ in true }
    #expect(workspace.sizes.isEmpty)
    #expect(workspace.firstVisible == WindowID(1))
  }
}

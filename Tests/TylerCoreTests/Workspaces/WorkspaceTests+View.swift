import CoreGraphics
import Testing

@testable import TylerCore

/// The strip's view on a workspace: four half windows in 1000 × 600 show two at a time.
@Suite("Strip layout: the view")
struct WorkspaceViewTests {
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
    workspace.placements(on: display, gaps: gaps).map(\.id)
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
    #expect(workspace.offView(on: display, gaps: gaps).count == 2)
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

  /// A change to the list of `strip(1, 2, 3, 4, focus: 2)`. The view starts at a window (1 here),
  /// so it moves with that window when the list is reordered, and refits when the focused window
  /// leaves it.
  enum ListChange: String, Sendable, CaseIterable {
    case insertAfterTheFocus, append, insertBeforeTheFirst, swapNextTwice, swapWithTheLast
    case syncDroppingOne, syncAddingTwo

    func apply(to workspace: inout Workspace) {
      switch self {
      case .insertAfterTheFocus: workspace.insert(WindowID(5))
      case .append: workspace.append(WindowID(5))
      case .insertBeforeTheFirst: workspace.insert(WindowID(5), before: WindowID(1))
      case .swapNextTwice:
        workspace.swap(.next)
        workspace.swap(.next)
      case .swapWithTheLast: workspace.swap(WindowID(1), with: WindowID(4))
      case .syncDroppingOne: workspace.sync(eligible: ids(1, 3, 4))
      case .syncAddingTwo: workspace.sync(eligible: ids(1, 2, 3, 4, 5, 6))
      }
    }
  }

  @Test(arguments: [
    (ListChange.insertAfterTheFocus, [UInt32(1), 2]),
    (ListChange.append, [UInt32(1), 2]),
    (ListChange.insertBeforeTheFirst, [UInt32(1), 2]),
    (ListChange.swapNextTwice, [UInt32(4), 2]),
    (ListChange.swapWithTheLast, [UInt32(2), 3]),
    (ListChange.syncDroppingOne, [UInt32(1), 3]),
    (ListChange.syncAddingTwo, [UInt32(1), 2]),
  ])
  func aListChangeRefitsTheView(change: ListChange, shown: [UInt32]) {
    var workspace = strip(1, 2, 3, 4, focus: 2)
    change.apply(to: &workspace)
    #expect(visible(workspace) == shown.map(WindowID.init))
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

  @Test func aWindowPartlyInViewShowsWhatFits() {
    var workspace = strip(1, 2, 3, focus: 1)
    workspace.setSize(.full, of: WindowID(2))
    #expect(visible(workspace) == ids(1, 2))
    #expect(
      workspace.restingPlacements(on: display, gaps: gaps)[1].frame
        == CGRect(x: 500, y: 0, width: 1000, height: 600))
  }

  /// A display with another one to its right parks on the left.
  @Test func aWindowPartlyInViewParksAtAnEdgeWithANeighbour() {
    var display = display
    display.neighbours = [.right]
    display.parkingEdge = .left
    var workspace = strip(1, 2, 3, focus: 1)
    workspace.setSize(.full, of: WindowID(2))
    #expect(workspace.placements(on: display, gaps: gaps).map(\.id) == ids(1))
    #expect(
      workspace.restingPlacements(on: display, gaps: gaps)[1].frame
        == CGRect(x: -999, y: 0, width: 1000, height: 600))
  }

  @Test func windowsOutOfViewRestParked() {
    let workspace = strip(1, 2, 3, 4, focus: 1)
    let resting = workspace.restingPlacements(on: display, gaps: gaps)
    #expect(resting[1].frame == CGRect(x: 500, y: 0, width: 500, height: 600))
    #expect(resting[2].frame == CGRect(x: 999, y: 0, width: 500, height: 600))
    #expect(resting[3].frame == CGRect(x: 999, y: 0, width: 500, height: 600))
  }

  @Test func switchingToTheStripFitsTheViewToTheFocus() {
    var workspace = strip(1, 2, 3, 4, focus: 1)
    workspace.layout = .tall
    workspace.setFocus(WindowID(4))
    #expect(workspace.firstVisible == WindowID(1), "tall doesn't scroll")
    workspace.layout = .strip
    #expect(visible(workspace) == ids(3, 4))
  }

  @Test func otherLayoutsShowEveryWindow() {
    var workspace = strip(1, 2, 3, 4, focus: 4)
    workspace.layout = .tall
    #expect(visible(workspace) == ids(1, 2, 3, 4))
    #expect(workspace.offView(on: display, gaps: gaps).isEmpty)
    #expect(
      workspace.restingPlacements(on: display, gaps: gaps)
        == workspace.placements(on: display, gaps: gaps))
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
    var workspace = saved.workspace { _ in true }
    #expect(workspace.layoutStates.strip.sizes.isEmpty)
    workspace.layout = .strip
    #expect(workspace.firstVisible == WindowID(1))
  }
}

import CoreGraphics
import Testing

@testable import TylerCore

@Suite("Workspace")
struct WorkspaceTests {
  // MARK: - Insert and remove

  @Test func insertWithoutFocusAppends() {
    var workspace = Workspace()
    workspace.insert(WindowID(1))
    workspace.insert(WindowID(2))
    #expect(workspace.windows == ids(1, 2))
  }

  @Test func insertGoesAfterTheFocusedWindow() {
    var workspace = makeWorkspace(1, 2, 3, focus: 1)
    workspace.insert(WindowID(9))
    #expect(workspace.windows == ids(1, 9, 2, 3))
  }

  @Test func insertingTwiceIsANoOp() {
    var workspace = makeWorkspace(1, 2)
    let inserted = workspace.insert(WindowID(1))
    #expect(!inserted)
    #expect(workspace.windows == ids(1, 2))
  }

  @Test func removingTheFocusedWindowFocusesTheOneThatTookItsPlace() {
    var workspace = makeWorkspace(1, 2, 3, focus: 2)
    workspace.remove(WindowID(2))
    #expect(workspace.windows == ids(1, 3))
    #expect(workspace.focused == WindowID(3))
  }

  @Test func removingTheFocusedLastWindowFocusesTheNewLast() {
    var workspace = makeWorkspace(1, 2, 3, focus: 3)
    workspace.remove(WindowID(3))
    #expect(workspace.focused == WindowID(2))
  }

  @Test func removingTheOnlyWindowClearsFocus() {
    var workspace = makeWorkspace(1, focus: 1)
    workspace.remove(WindowID(1))
    #expect(workspace.windows.isEmpty)
    #expect(workspace.focused == nil)
  }

  @Test func removingAnotherWindowKeepsFocus() {
    var workspace = makeWorkspace(1, 2, 3, focus: 2)
    workspace.remove(WindowID(1))
    #expect(workspace.focused == WindowID(2))
  }

  @Test func removingAnUnknownWindowIsANoOp() {
    var workspace = makeWorkspace(1, 2)
    let removed = workspace.remove(WindowID(99))
    #expect(!removed)
    #expect(workspace.windows == ids(1, 2))
  }

  // MARK: - Focus

  @Test func focusNextWrapsAround() {
    var workspace = makeWorkspace(1, 2, 3, focus: 3)
    let focusedWindow = workspace.focus(.next)
    #expect(focusedWindow == WindowID(1))
  }

  @Test func focusPrevWrapsAround() {
    var workspace = makeWorkspace(1, 2, 3, focus: 1)
    let focusedWindow = workspace.focus(.prev)
    #expect(focusedWindow == WindowID(3))
  }

  @Test func focusMainGoesToTheFirstWindow() {
    var workspace = makeWorkspace(1, 2, 3, focus: 3)
    let focusedWindow = workspace.focus(.main)
    #expect(focusedWindow == WindowID(1))
  }

  @Test func withNothingFocusedNextAndMainPickFirstAndPrevPicksLast() {
    var workspace = makeWorkspace(1, 2, 3)
    let focusedWindow = workspace.focus(.next)
    #expect(focusedWindow == WindowID(1))
    workspace = makeWorkspace(1, 2, 3)
    let focusedWindow2 = workspace.focus(.main)
    #expect(focusedWindow2 == WindowID(1))
    workspace = makeWorkspace(1, 2, 3)
    let focusedWindow3 = workspace.focus(.prev)
    #expect(focusedWindow3 == WindowID(3))
  }

  @Test func focusOnASingleWindowStaysPut() {
    var workspace = makeWorkspace(1, focus: 1)
    for target in ListTarget.allCases {
      let focusedWindow = workspace.focus(target)
      #expect(focusedWindow == WindowID(1))
    }
  }

  @Test func focusOnAnEmptyWorkspaceDoesNothing() {
    var workspace = Workspace()
    for target in ListTarget.allCases {
      let focusedWindow = workspace.focus(target)
      #expect(focusedWindow == nil)
    }
  }

  @Test func setFocusIgnoresWindowsThatAreNotTiled() {
    var workspace = makeWorkspace(1, 2, focus: 1)
    let didChange = workspace.setFocus(WindowID(99))
    #expect(!didChange)
    #expect(workspace.focused == WindowID(1))
  }

  @Test func setFocusReportsWhetherItChanged() {
    var workspace = makeWorkspace(1, 2, focus: 1)
    let didChange = workspace.setFocus(WindowID(1))
    #expect(!didChange)
    let didChange2 = workspace.setFocus(WindowID(2))
    #expect(didChange2)
  }

  // MARK: - Swap

  @Test func swapNextMovesTheFocusedWindowAndKeepsFocusOnIt() {
    var workspace = makeWorkspace(1, 2, 3, focus: 1)
    let swapped = workspace.swap(.next)
    #expect(swapped)
    #expect(workspace.windows == ids(2, 1, 3))
    #expect(workspace.focused == WindowID(1))
  }

  @Test func swapNextWrapsFromTheLastWindow() {
    var workspace = makeWorkspace(1, 2, 3, focus: 3)
    workspace.swap(.next)
    #expect(workspace.windows == ids(3, 2, 1))
  }

  @Test func swapPrevWrapsFromTheFirstWindow() {
    var workspace = makeWorkspace(1, 2, 3, focus: 1)
    workspace.swap(.prev)
    #expect(workspace.windows == ids(3, 2, 1))
  }

  @Test func swapMainBringsTheFocusedWindowToTheFront() {
    var workspace = makeWorkspace(1, 2, 3, focus: 3)
    workspace.swap(.main)
    #expect(workspace.windows == ids(3, 2, 1))
    #expect(workspace.focused == WindowID(3))
  }

  @Test func swapMainOnTheMainSwapsWithTheSecondWindow() {
    var workspace = makeWorkspace(1, 2, 3, focus: 1)
    workspace.swap(.main)
    #expect(workspace.windows == ids(2, 1, 3))
  }

  @Test func swapNeedsAtLeastTwoWindowsAndAFocus() {
    var single = makeWorkspace(1, focus: 1)
    let swapped = single.swap(.next)
    #expect(!swapped)
    var unfocused = makeWorkspace(1, 2)
    let swapped2 = unfocused.swap(.next)
    #expect(!swapped2)
    #expect(unfocused.windows == ids(1, 2))
  }

  // MARK: - Sync

  @Test func syncKeepsTheOrderOfSurvivors() {
    var workspace = makeWorkspace(3, 1, 2)
    let changed = workspace.sync(eligible: ids(1, 2, 3))
    #expect(changed == false)
    #expect(workspace.windows == ids(3, 1, 2))
  }

  @Test func syncDropsWindowsThatAreNoLongerEligible() {
    var workspace = makeWorkspace(1, 2, 3)
    let changed = workspace.sync(eligible: ids(1, 3))
    #expect(changed)
    #expect(workspace.windows == ids(1, 3))
  }

  @Test func syncInsertsNewWindowsAfterTheFocusedOneInTheOrderGiven() {
    var workspace = makeWorkspace(1, 2, focus: 1)
    let changed = workspace.sync(eligible: ids(1, 2, 8, 9))
    #expect(changed)
    #expect(workspace.windows == ids(1, 8, 9, 2))
  }

  @Test func syncAppendsNewWindowsWhenNothingIsFocused() {
    var workspace = makeWorkspace(1)
    workspace.sync(eligible: ids(1, 5))
    #expect(workspace.windows == ids(1, 5))
  }

  @Test func syncFromEmptyOrdersByTheGivenOrder() {
    var workspace = Workspace()
    let changed = workspace.sync(eligible: ids(4, 2, 7))
    #expect(changed)
    #expect(workspace.windows == ids(4, 2, 7))
  }

  @Test func syncFixesFocusWhenTheFocusedWindowGoes() {
    var workspace = makeWorkspace(1, 2, 3, focus: 2)
    workspace.sync(eligible: ids(1, 3))
    #expect(workspace.focused == WindowID(3))
  }

  @Test func syncWithNothingEligibleEmptiesTheWorkspace() {
    var workspace = makeWorkspace(1, 2, focus: 1)
    let changed = workspace.sync(eligible: [])
    #expect(changed)
    #expect(workspace.windows.isEmpty)
    #expect(workspace.focused == nil)
  }

  // MARK: - Slots, layout and placements

  @Test func slotsAreOneBasedWithTheMainFirst() {
    let workspace = makeWorkspace(5, 6, 7)
    #expect(workspace.slot(of: WindowID(5)) == 1)
    #expect(workspace.slot(of: WindowID(7)) == 3)
    #expect(workspace.slot(of: WindowID(99)) == nil)
  }

  @Test func placementsFollowListOrder() {
    let workspace = makeWorkspace(5, 6, 7)
    let placements = workspace.placements(in: CGRect(x: 0, y: 0, width: 1000, height: 600))
    #expect(placements.map(\.id) == ids(5, 6, 7))
    #expect(placements[0].frame == CGRect(x: 0, y: 0, width: 500, height: 600))
    #expect(placements[1].frame == CGRect(x: 500, y: 0, width: 500, height: 300))
  }

  @Test func swappingChangesWhichWindowGetsTheMainFrame() {
    var workspace = makeWorkspace(5, 6, focus: 6)
    workspace.swap(.main)
    let placements = workspace.placements(in: CGRect(x: 0, y: 0, width: 1000, height: 600))
    #expect(placements[0].id == WindowID(6))
    #expect(placements[0].frame.minX == 0)
  }

  @Test func cyclingTheLayoutChangesPlacements() {
    var workspace = makeWorkspace(5, 6)
    workspace.cycleLayout()
    #expect(workspace.layout == .full)
    let placements = workspace.placements(in: CGRect(x: 0, y: 0, width: 1000, height: 600))
    #expect(placements[0].frame == placements[1].frame)
  }

  @Test func ratioChangesAffectPlacements() {
    var workspace = makeWorkspace(5, 6)
    let didChange = workspace.adjustRatio(by: 0.1)
    #expect(didChange)
    let placements = workspace.placements(in: CGRect(x: 0, y: 0, width: 1000, height: 600))
    #expect(placements[0].frame.width == 600)
  }

  @Test func anEmptyWorkspaceHasNoPlacements() {
    #expect(Workspace().placements(in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
  }

  // MARK: - Resizing with the mouse

  @Test func resizingAWindowMovesTheDividersOfItsSlot() {
    var workspace = makeWorkspace(1, 2, 3)
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let changed = workspace.resize(
      WindowID(2), to: CGRect(x: 300, y: 0, width: 700, height: 300), in: area)
    #expect(changed)
    #expect(workspace.parameters.mainRatio == 0.3)
    #expect(workspace.placements(in: area)[0].frame.width == 300)
  }

  @Test func resizingAnUnknownWindowOrAnImmovableEdgeChangesNothing() {
    var workspace = makeWorkspace(1, 2, 3)
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let unknown = workspace.resize(
      WindowID(9), to: CGRect(x: 300, y: 0, width: 700, height: 300), in: area)
    let outerEdge = workspace.resize(
      WindowID(1), to: CGRect(x: 0, y: 40, width: 500, height: 560), in: area)
    #expect(!unknown)
    #expect(!outerEdge)
    #expect(workspace.parameters == LayoutParameters())
  }

  @Test func resizingInFullChangesNothing() {
    var workspace = makeWorkspace(1, 2)
    workspace.layout = .full
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let changed = workspace.resize(
      WindowID(1), to: CGRect(x: 0, y: 0, width: 600, height: 600), in: area)
    #expect(!changed)
  }
}

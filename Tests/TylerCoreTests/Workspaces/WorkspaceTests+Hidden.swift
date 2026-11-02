import CoreGraphics
import Testing

@testable import TylerCore

/// A hidden member takes no slot and keeps its place in the list.
@Suite("Workspace: hidden members")
struct WorkspaceHiddenTests {
  private func hiding(_ hidden: UInt32, in workspace: Workspace) -> Workspace {
    var workspace = workspace
    workspace.hide(WindowID(hidden))
    return workspace
  }

  @Test func aHiddenWindowTakesNoSlotButStaysAMember() {
    let workspace = hiding(2, in: makeWorkspace(1, 2, 3))
    #expect(workspace.windows == ids(1, 3))
    #expect(workspace.members == ids(1, 2, 3))
    #expect(workspace.hidden == [WindowID(2)])
    #expect(!workspace.contains(WindowID(2)))
  }

  @Test func withNothingHiddenTheMembersAreTheTiledWindows() {
    var workspace = makeWorkspace(1, 2, 3, focus: 1)
    workspace.swap(.next)
    workspace.remove(WindowID(3))
    #expect(workspace.members == workspace.windows)
  }

  @Test func onlyATiledWindowCanBeHidden() {
    var workspace = makeWorkspace(1, 2)
    let result1 = workspace.hide(WindowID(9))
    #expect(!result1)
    #expect(workspace.hidden.isEmpty)
    let result2 = workspace.show(WindowID(1))
    #expect(!result2)
  }

  @Test func showingPutsTheWindowBackInItsPlace() {
    var workspace = hiding(2, in: makeWorkspace(1, 2, 3))
    let result3 = workspace.show(WindowID(2))
    #expect(result3)
    #expect(workspace.windows == ids(1, 2, 3))
    #expect(workspace.members == ids(1, 2, 3))
    #expect(workspace.hidden.isEmpty)
  }

  @Test func theFirstWindowComesBackFirst() {
    var workspace = hiding(1, in: makeWorkspace(1, 2, 3))
    #expect(workspace.windows == ids(2, 3))
    workspace.show(WindowID(1))
    #expect(workspace.windows == ids(1, 2, 3))
  }

  @Test func theLastWindowComesBackLast() {
    var workspace = hiding(3, in: makeWorkspace(1, 2, 3))
    workspace.show(WindowID(3))
    #expect(workspace.windows == ids(1, 2, 3))
  }

  @Test(arguments: [ids(1, 2, 3), ids(3, 2, 1), ids(2, 1, 3)])
  func windowsHiddenTogetherComeBackInOrderWhicheverReturnsFirst(_ order: [WindowID]) {
    var workspace = makeWorkspace(1, 2, 3, 4)
    for windowID in ids(1, 2, 3) { workspace.hide(windowID) }
    #expect(workspace.windows == ids(4))
    for windowID in order { workspace.show(windowID) }
    #expect(workspace.windows == ids(1, 2, 3, 4))
  }

  @Test func aHiddenWindowStaysBeforeTheWindowThatFollowedIt() {
    var workspace = hiding(2, in: makeWorkspace(1, 2, 3, focus: 3))
    workspace.swap(.prev)
    #expect(workspace.windows == ids(3, 1))
    #expect(workspace.members == ids(2, 3, 1))
    workspace.show(WindowID(2))
    #expect(workspace.windows == ids(2, 3, 1))
  }

  @Test func aWindowClosingBesideAHiddenOneLeavesItsPlace() {
    var workspace = hiding(2, in: makeWorkspace(1, 2, 3, 4))
    workspace.remove(WindowID(3))
    #expect(workspace.members == ids(1, 2, 4))
    workspace.show(WindowID(2))
    #expect(workspace.windows == ids(1, 2, 4))
  }

  @Test func aNewWindowLeavesAHiddenOneInPlace() {
    var workspace = hiding(2, in: makeWorkspace(1, 2, 3, focus: 3))
    workspace.insert(WindowID(9))
    #expect(workspace.windows == ids(1, 3, 9))
    #expect(workspace.members == ids(1, 2, 3, 9))
  }

  @Test func removingAHiddenWindowForgetsIt() {
    var workspace = hiding(2, in: makeWorkspace(1, 2, 3))
    let result4 = workspace.remove(WindowID(2))
    #expect(result4)
    #expect(workspace.members == ids(1, 3))
    #expect(workspace.hidden.isEmpty)
  }

  @Test func hidingTheFocusedWindowMovesTheFocusOn() {
    let workspace = hiding(2, in: makeWorkspace(1, 2, 3, focus: 2))
    #expect(workspace.focused == WindowID(3))
  }

  @Test func syncHidesAndShowsAndDropsMembers() {
    var workspace = makeWorkspace(1, 2, 3)
    let result5 = workspace.sync(eligible: ids(1, 3), hiding: [WindowID(2)])
    #expect(result5)
    #expect(workspace.members == ids(1, 2, 3))
    let result6 = workspace.sync(eligible: ids(1, 3), hiding: [WindowID(2)])
    #expect(!result6)
    let result7 = workspace.sync(eligible: ids(1, 2, 3))
    #expect(result7)
    #expect(workspace.windows == ids(1, 2, 3))
    #expect(workspace.hidden.isEmpty)
  }

  @Test func syncDropsAHiddenWindowThatIsGone() {
    var workspace = hiding(2, in: makeWorkspace(1, 2, 3))
    let result8 = workspace.sync(eligible: ids(1, 3))
    #expect(result8)
    #expect(workspace.members == ids(1, 3))
  }

  @Test(arguments: LayoutKind.allCases)
  func aHiddenMemberChangesNoFrame(layout: LayoutKind) {
    let area = CGRect(x: 0, y: 0, width: 1200, height: 800)
    var withHidden = hiding(2, in: makeWorkspace(1, 2, 3))
    withHidden.layout = layout
    var without = makeWorkspace(1, 3)
    without.layout = layout
    #expect(
      withHidden.arrangement(in: area, gaps: LayoutGaps())
        == without.arrangement(in: area, gaps: LayoutGaps()))
  }

  @Test func aRowsWindowsIncludeHiddenMembers() {
    var row = WorkspaceRow(count: 2)
    row[0] = hiding(2, in: makeWorkspace(1, 2))
    #expect(row.allWindows == Set(ids(1, 2)))
  }

  @Test func aRemovedWorkspaceHandsOverItsHiddenMembers() {
    var row = WorkspaceRow(count: 2)
    row[1] = hiding(2, in: makeWorkspace(1, 2))
    row.setNumbers([1])
    #expect(row[0].members == ids(1, 2))
  }
}

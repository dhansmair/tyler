import Testing

@testable import TylerCore

@Suite("Workspace: the master section")
struct WorkspaceMainSectionTests {
  /// Windows 1 to 4 with `mains` of them in the master section, `focus` focused.
  private func workspace(mains: Int, focus: UInt32) -> Workspace {
    var workspace = makeWorkspace(1, 2, 3, 4, focus: focus)
    workspace.update(\.tall) { state, _ in state = TallLayoutState(mainCount: mains) }
    return workspace
  }

  @Test func promotingMovesTheWindowToTheEndOfTheMainSection() {
    var workspace = workspace(mains: 1, focus: 3)
    let changed = workspace.promote()
    #expect(changed)
    #expect(workspace.windows == ids(1, 3, 2, 4))
    #expect(workspace.mainSectionCount == 2)
    #expect(workspace.focused == WindowID(3))
  }

  @Test func promotingTheLastStackedWindowLeavesNoStack() {
    var workspace = workspace(mains: 3, focus: 4)
    let changed = workspace.promote()
    #expect(changed)
    #expect(workspace.mainSectionCount == 4)
  }

  @Test func promotingAMainChangesNothing() {
    var workspace = workspace(mains: 2, focus: 2)
    let changed = workspace.promote()
    #expect(!changed)
    #expect(workspace.windows == ids(1, 2, 3, 4))
    #expect(workspace.mainSectionCount == 2)
  }

  @Test func demotingMovesTheWindowToTheTopOfTheStack() {
    var workspace = workspace(mains: 3, focus: 1)
    let changed = workspace.demote()
    #expect(changed)
    #expect(workspace.windows == ids(2, 3, 1, 4))
    #expect(workspace.mainSectionCount == 2)
  }

  @Test func demotingTheOnlyMainMakesTheNextWindowTheMain() {
    var workspace = workspace(mains: 1, focus: 1)
    let changed = workspace.demote()
    #expect(changed)
    #expect(workspace.windows == ids(2, 1, 3, 4))
    #expect(workspace.mainSectionCount == 1)
  }

  @Test func demotingAStackedWindowChangesNothing() {
    var workspace = workspace(mains: 2, focus: 3)
    let changed = workspace.demote()
    #expect(!changed)
    #expect(workspace.windows == ids(1, 2, 3, 4))
  }

  @Test func demotingTheOnlyWindowChangesNothing() {
    var workspace = makeWorkspace(1, focus: 1)
    let changed = workspace.demote()
    #expect(!changed)
  }

  @Test func nothingFocusedPromotesAndDemotesNothing() {
    var workspace = makeWorkspace(1, 2)
    let promoted = workspace.promote()
    let demoted = workspace.demote()
    #expect(!promoted && !demoted)
  }

  @Test func aNewWindowGoesIntoTheStackWhenAMainHasFocus() {
    var workspace = workspace(mains: 2, focus: 1)
    workspace.insert(WindowID(9))
    #expect(workspace.windows == ids(1, 2, 9, 3, 4))
    #expect(workspace.mainSectionCount == 2)
  }

  @Test func aNewWindowStillGoesAfterTheFocusedOneInTheStack() {
    var workspace = workspace(mains: 2, focus: 3)
    workspace.insert(WindowID(9))
    #expect(workspace.windows == ids(1, 2, 3, 9, 4))
  }

  @Test func outsideTallANewWindowGoesAfterTheFocusedOne() {
    var workspace = workspace(mains: 2, focus: 1)
    workspace.layout = .grid
    workspace.insert(WindowID(9))
    #expect(workspace.windows == ids(1, 9, 2, 3, 4))
  }

  @Test func newWindowsFromASyncGoIntoTheStack() {
    var workspace = workspace(mains: 2, focus: 1)
    workspace.sync(eligible: ids(1, 2, 3, 4, 8, 9))
    #expect(workspace.windows == ids(1, 2, 8, 9, 3, 4))
  }

  @Test func closingAMainShrinksTheSection() {
    var workspace = workspace(mains: 2, focus: 1)
    workspace.remove(WindowID(2))
    #expect(workspace.mainSectionCount == 1)
    #expect(workspace.windows == ids(1, 3, 4))
  }
}

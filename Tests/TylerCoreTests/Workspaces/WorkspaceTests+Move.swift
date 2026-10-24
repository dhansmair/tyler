import Testing

@testable import TylerCore

@Suite("Workspace: moving a window to a slot")
struct WorkspaceMoveTests {
  @Test func aWindowMovesToItsSlotAndTheOthersCloseUp() {
    var workspace = makeWorkspace(1, 2, 3)
    let moved = workspace.move(WindowID(3), toSlot: 1)
    #expect(moved)
    #expect(workspace.windows == ids(3, 1, 2))
  }

  @Test func aSlotPastTheEndPutsTheWindowLast() {
    var workspace = makeWorkspace(1, 2, 3)
    let moved = workspace.move(WindowID(1), toSlot: 7)
    #expect(moved)
    #expect(workspace.windows == ids(2, 3, 1))
  }

  @Test func aWindowNotInTheListOrAlreadyThereDoesNotMove() {
    var workspace = makeWorkspace(1, 2)
    let movedAWindowNotInTheList = workspace.move(WindowID(9), toSlot: 1)
    let movedAWindowAlreadyThere = workspace.move(WindowID(2), toSlot: 2)
    #expect(!movedAWindowNotInTheList && !movedAWindowAlreadyThere)
    #expect(workspace.windows == ids(1, 2))
  }
}

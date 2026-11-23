import Testing

@testable import TylerCore

@Suite("Workspace: the window that takes a window's place")
struct WorkspaceSuccessorTests {
  @Test(arguments: [
    (leaving: UInt32(1), successor: UInt32(2)),
    (leaving: 2, successor: 3),
    (leaving: 3, successor: 2),
  ])
  func aTiledWindowIsFollowedByTheNextOrTheNewLast(leaving: UInt32, successor: UInt32) {
    let workspace = makeWorkspace(1, 2, 3)
    #expect(workspace.successor(of: WindowID(leaving)) == WindowID(successor))
  }

  @Test func theOnlyWindowHasNone() {
    #expect(makeWorkspace(1).successor(of: WindowID(1)) == nil)
  }

  @Test func aWindowOffTheWorkspaceHasNone() {
    #expect(makeWorkspace(1, 2).successor(of: WindowID(9)) == nil)
  }

  @Test func aFloatingWindowHasNone() {
    var workspace = makeWorkspace(1, 2, 3)
    workspace.float(WindowID(2))
    #expect(workspace.successor(of: WindowID(2)) == nil)
  }

  @Test func aFloatingWindowIsSkipped() {
    var workspace = makeWorkspace(1, 2, 3)
    workspace.float(WindowID(2))
    #expect(workspace.successor(of: WindowID(1)) == WindowID(3))
  }
}

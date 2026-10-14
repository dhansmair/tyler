import Testing

@testable import TylerCore

@Suite("WorkspaceTarget")
struct WorkspaceTargetTests {
  @Test(arguments: [
    (WorkspaceTarget.prev, 0, 3, ScrollDirection.prev),
    (.next, 3, 0, .next),
    (.number(3), 0, 2, .next),
    (.number(1), 2, 0, .prev),
  ])
  func aTargetScrollsTheRowItsWay(
    target: WorkspaceTarget, source: Int, index: Int, direction: ScrollDirection
  ) {
    #expect(target.direction(from: source, to: index) == direction)
  }
}

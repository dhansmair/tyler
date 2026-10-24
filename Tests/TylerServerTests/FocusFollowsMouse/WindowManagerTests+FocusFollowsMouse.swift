import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("WindowManager: the pointer's log lines")
@MainActor
struct WindowManagerFocusFollowsMouseTests {
  @Test func theLogNamesTheWindowOnTopByItsAppOrOwner() async {
    let stacking = FakeStacking()
    let harness = ManagerHarness([1, 2, 3], stacking: stacking)
    await harness.settle()
    let cursor = StackedWindow(id: WindowID(900), layer: 25, owner: "Window Server")
    stacking.overlays = [(cursor, CGRect(x: 1290, y: 290, width: 28, height: 40))]
    let manager = harness.manager
    let untracked = CGPoint(x: 1300, y: 300)
    let tracked = CGPoint(x: 400, y: 600)
    let empty = CGPoint(x: 5000, y: 5000)
    #expect(
      manager.pointerLogSubject(untracked, manager.pointerCheck(at: untracked))
        == "1300,300 - #900 (Window Server)")
    let name = manager.named(WindowID(1))
    #expect(
      manager.pointerLogSubject(tracked, manager.pointerCheck(at: tracked)) == "400,600 - \(name)")
    #expect(manager.pointerLogSubject(empty, manager.pointerCheck(at: empty)) == "5000,5000")
  }
}

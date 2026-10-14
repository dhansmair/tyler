import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// `tyler debug at`. Windows 1, 2 and 3 tile `tall` on the fake display: window 1 on the left,
/// 2 above 3 on the right. Window 1 has focus.
@Suite("debug at")
@MainActor
struct DebugAtScenarios {
  private let pointer = FakePointer()
  private let stacking = FakeStacking()

  private func makeHarness() async -> ManagerHarness {
    var config = Config()
    config.mouse.focusFollows = true
    let harness = ManagerHarness(
      [1, 2, 3], config: config, pointer: pointer, stacking: stacking, clock: TestClock())
    await harness.osFocus(1)
    return harness
  }

  private func diagnosis(at point: CGPoint?, in harness: ManagerHarness) -> PointerDiagnosis? {
    guard case .pointer(let diagnosis) = harness.manager.handle(.debugAt(point)) else {
      return nil
    }
    return diagnosis
  }

  @Test func aWindowInViewIsDescribedAndWouldBeGrabbedAndFocused() async throws {
    let harness = await makeHarness()
    let diagnosis = try #require(self.diagnosis(at: CGPoint(x: 1300, y: 300), in: harness))
    #expect(diagnosis.displayNumber == 1)
    #expect(diagnosis.visibleFrame == FakeDisplays.main.visibleFrame)
    #expect(diagnosis.onTop?.id == WindowID(2))
    #expect(diagnosis.onTop?.workspace == 1)
    #expect(diagnosis.onTop?.appName != nil)
    #expect(diagnosis.interaction == "idle")
    #expect(diagnosis.modifier == "option")
    #expect(diagnosis.grab == .window(WindowID(2)))
    #expect(diagnosis.focus == .window(WindowID(2)))
  }

  @Test func theReasonsAreTheRealDecisions() async throws {
    let harness = await makeHarness()
    let focused = try #require(self.diagnosis(at: CGPoint(x: 400, y: 600), in: harness))
    #expect(focused.focus == .refused(.alreadyFocused))
    _ = harness.manager.setTiling(.off)
    let off = try #require(self.diagnosis(at: CGPoint(x: 1300, y: 300), in: harness))
    #expect(off.grab == .refused(.tilingOff))
    #expect(!pointer.wouldGrab(at: CGPoint(x: 1300, y: 300)))
  }

  @Test func theMenuBarIsOutsideEveryVisibleFrame() async throws {
    let harness = await makeHarness()
    let diagnosis = try #require(self.diagnosis(at: CGPoint(x: 400, y: 10), in: harness))
    #expect(diagnosis.displayNumber == 1, "on the display, but not in its visible frame")
    #expect(diagnosis.grab == .refused(.outsideDisplays))
  }

  @Test func aWindowTylerdDoesNotTrackIsNamedByItsOwner() async throws {
    let harness = await makeHarness()
    let cursor = StackedWindow(id: WindowID(900), layer: 25, owner: "Window Server")
    stacking.overlays = [(cursor, CGRect(x: 1290, y: 290, width: 28, height: 40))]
    let diagnosis = try #require(self.diagnosis(at: CGPoint(x: 1300, y: 300), in: harness))
    #expect(diagnosis.onTop?.owner == "Window Server")
    #expect(diagnosis.onTop?.appName == nil)
  }

  @Test func theLogNamesTheWindowOnTopByItsAppOrOwner() async throws {
    let harness = await makeHarness()
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

  @Test func withoutAPointItSaysSo() async {
    let harness = await makeHarness()
    #expect(harness.manager.handle(.debugAt(nil)) == .error("debug at needs a point on screen"))
  }
}

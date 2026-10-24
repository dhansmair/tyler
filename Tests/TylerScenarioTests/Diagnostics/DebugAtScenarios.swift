import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerProtocol
import TylerTestSupport

/// `tyler debug at`. Windows 1, 2 and 3 tile `tall` on the fake display: window 1 on the left,
/// 2 above 3 on the right. Window 1 has focus.
@Suite("debug at")
@MainActor
struct DebugAtScenarios {
  private func scenario() async -> Scenario {
    var config = Config()
    config.mouse.focusFollows = true
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]], config: config)
    await scenario.focus(1)
    return scenario
  }

  private func diagnosis(at point: CGPoint, in scenario: Scenario) async -> PointerDiagnosis? {
    guard
      case .pointer(let diagnosis) = await scenario.command(
        "debug at \(Int(point.x)) \(Int(point.y))")
    else { return nil }
    return diagnosis
  }

  @Test func aWindowInViewIsDescribedAndWouldBeGrabbedAndFocused() async throws {
    let scenario = await scenario()
    let diagnosis = try #require(await diagnosis(at: CGPoint(x: 1300, y: 300), in: scenario))
    #expect(diagnosis.displayNumber == 1)
    #expect(diagnosis.visibleFrame == scenario.rect(.full))
    #expect(diagnosis.onTop?.id == WindowID(2))
    #expect(diagnosis.onTop?.workspace == 1)
    #expect(diagnosis.onTop?.appName != nil)
    #expect(diagnosis.interaction == "idle")
    #expect(diagnosis.modifier == "option")
    #expect(diagnosis.grab == .window(WindowID(2)))
    #expect(diagnosis.focus == .window(WindowID(2)))
  }

  @Test func theReasonsAreTheRealDecisions() async throws {
    let scenario = await scenario()
    let focused = try #require(await diagnosis(at: CGPoint(x: 400, y: 600), in: scenario))
    #expect(focused.focus == .refused(.alreadyFocused))
    await scenario.command("tiling off")
    let off = try #require(await diagnosis(at: CGPoint(x: 1300, y: 300), in: scenario))
    #expect(off.grab == .refused(.tilingOff))
    #expect(!scenario.pointer.wouldGrab(at: CGPoint(x: 1300, y: 300)))
  }

  @Test func theMenuBarIsOutsideEveryVisibleFrame() async throws {
    let scenario = await scenario()
    let diagnosis = try #require(await diagnosis(at: CGPoint(x: 400, y: 10), in: scenario))
    #expect(diagnosis.displayNumber == 1, "on the display, but not in its visible frame")
    #expect(diagnosis.grab == .refused(.outsideDisplays))
  }

  @Test func aWindowTylerdDoesNotTrackIsNamedByItsOwner() async throws {
    let scenario = await scenario()
    let cursor = StackedWindow(id: WindowID(900), layer: 25, owner: "Window Server")
    scenario.stacking.overlays = [(cursor, CGRect(x: 1290, y: 290, width: 28, height: 40))]
    let diagnosis = try #require(await diagnosis(at: CGPoint(x: 1300, y: 300), in: scenario))
    #expect(diagnosis.onTop?.owner == "Window Server")
    #expect(diagnosis.onTop?.appName == nil)
  }

  @Test func withoutAPointItSaysSo() async {
    let scenario = await scenario()
    #expect(await scenario.send(.debugAt(nil)) == .error("debug at needs a point on screen"))
  }
}

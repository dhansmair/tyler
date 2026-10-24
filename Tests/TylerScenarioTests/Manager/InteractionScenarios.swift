import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

/// A slide, a trackpad swipe and a mouse drag never run at the same time: whichever comes second
/// is ignored or ends the first. Windows 1 and 2 tile workspace 1, window 3 waits on workspace 2.
@Suite("Slide, swipe and drag exclude each other")
@MainActor
struct InteractionScenarios {
  private func scenario(animates: Bool = false) async -> Scenario {
    let scenario = await Scenario(
      workspaces: [1: [1, 2], 2: [3]], animates: animates, slide: .milliseconds(48),
      frameInterval: .milliseconds(16))
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  /// The user resizes window 1 with the button down, by `inset` points at the top and bottom.
  private func resizeWindow1(by inset: CGFloat, in scenario: Scenario) async {
    scenario.pointer.isPrimaryButtonDown = true
    let frame = scenario.frame(of: 1) ?? .zero
    await scenario.moveByHand(1, to: frame.insetBy(dx: 0, dy: inset))
  }

  @Test func aSwipeDuringADragIsIgnored() async throws {
    let scenario = await scenario()
    await resizeWindow1(by: 50, in: scenario)
    scenario.windowSystem.clearRecordedCalls()
    let before = scenario.frame(of: 2)
    scenario.pointer.swipe(.began)
    scenario.pointer.swipe(.moved(offset: -0.15))
    await scenario.runUntilQuiet()
    #expect(scenario.windowSystem.nudges.isEmpty, "the fingers move nothing")
    #expect(scenario.frame(of: 2) == before)

    var wider = try #require(scenario.frame(of: 1))
    wider.size.width += 100
    await scenario.moveByHand(1, to: wider)
    #expect(scenario.frame(of: 2) != before, "the drag goes on: window 2 follows the resize")
  }

  @Test func aResizeDuringASwipeIsNotFollowed() async {
    let scenario = await scenario()
    let size = scenario.frame(of: 2)?.size
    scenario.pointer.swipe(.began)
    scenario.pointer.swipe(.moved(offset: -0.18))
    await scenario.runUntilQuiet()
    await resizeWindow1(by: 50, in: scenario)
    #expect(scenario.frame(of: 2)?.size == size, "window 2 doesn't follow the resize")

    scenario.pointer.swipe(.ended(velocity: 0))
    await scenario.runUntilQuiet()
    #expect(scenario.shown == [2], "the swipe goes on")
  }

  @Test func aResizeDuringASlideIsNotFollowed() async {
    let scenario = await scenario(animates: true)
    let size = scenario.frame(of: 2)?.size
    await scenario.start("workspace focus next")
    await resizeWindow1(by: 50, in: scenario)
    #expect(scenario.frame(of: 2)?.size == size, "window 2 doesn't follow the resize")

    await scenario.runUntilQuiet()
    #expect(scenario.frame(of: 3) == scenario.rect(.full), "the slide goes on")
    #expect(scenario.isParked(2))
  }

  @Test func aSwipeEndsASlide() async {
    let scenario = await scenario(animates: true)
    await scenario.start("workspace focus next")
    scenario.pointer.swipe(.began)
    await scenario.harness.settle()
    #expect(scenario.shown == [2])
    #expect(scenario.frame(of: 3) == scenario.rect(.full), "the slide jumped to its end")

    scenario.windowSystem.clearRecordedCalls()
    scenario.pointer.swipe(.moved(offset: 0.05))
    await scenario.harness.settle()
    #expect(!scenario.windowSystem.nudges.isEmpty, "the swipe moves the windows")
  }
}

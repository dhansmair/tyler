import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// A slide, a trackpad swipe and a mouse drag never run at the same time: whichever comes second
/// is ignored or ends the first. Windows 1 and 2 tile workspace 1, window 3 waits on workspace 2.
@Suite("Slide, swipe and drag exclude each other")
@MainActor
struct InteractionScenarios {
  private let pointer = FakePointer()
  private let clock = TestClock()

  private func makeHarness(animator: Animator = .snap) async -> ManagerHarness {
    let harness = ManagerHarness([1, 2, 3], animator: animator, pointer: pointer, clock: clock)
    await harness.osFocus(3)
    _ = harness.manager.moveToWorkspace(.next, follow: false)
    while clock.hasSleepers {
      clock.advance(by: .milliseconds(16))
      await harness.settle()
    }
    await harness.settle()
    harness.backend.clearRecordedCalls()
    return harness
  }

  /// The user resizes window 1 with the button down, starting a drag.
  private func resizeWindow1(in harness: ManagerHarness) async {
    pointer.isPrimaryButtonDown = true
    let frame = harness.frame(of: 1) ?? .zero
    await harness.backend.userMoves(1, to: frame.insetBy(dx: 0, dy: 50))
  }

  @Test func aSwipeDuringADragIsIgnored() async {
    let harness = await makeHarness()
    await resizeWindow1(in: harness)
    #expect(harness.manager.drag != nil)
    pointer.swipe(.began)
    pointer.swipe(.moved(offset: -0.15))
    await harness.settle()
    #expect(harness.manager.swipe == nil)
    #expect(harness.manager.drag != nil, "the drag goes on")
    #expect(harness.backend.nudges.isEmpty)
  }

  @Test func aResizeDuringASwipeIsNotFollowed() async {
    let harness = await makeHarness()
    pointer.swipe(.began)
    pointer.swipe(.moved(offset: -0.15))
    await harness.settle()
    #expect(harness.manager.swipe != nil)
    await resizeWindow1(in: harness)
    #expect(harness.manager.drag == nil)
    #expect(harness.manager.swipe != nil, "the swipe goes on")
  }

  @Test func aResizeDuringASlideIsNotFollowed() async {
    let animator = Animator(
      duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: clock)
    let harness = await makeHarness(animator: animator)
    _ = harness.manager.switchWorkspace(.next)
    #expect(harness.manager.slide != nil)
    await resizeWindow1(in: harness)
    #expect(harness.manager.drag == nil)
    #expect(harness.manager.slide != nil, "the slide goes on")
  }

  @Test func aSwipeEndsASlide() async {
    let animator = Animator(
      duration: .milliseconds(48), frameInterval: .milliseconds(16), clock: clock)
    let harness = await makeHarness(animator: animator)
    _ = harness.manager.switchWorkspace(.next)
    pointer.swipe(.began)
    await harness.settle()
    #expect(harness.manager.slide == nil)
    #expect(harness.manager.workspaces.currentIndex == 1)
    #expect(harness.frame(of: 3) == harness.area, "the slide jumped to its end")
    #expect(harness.manager.swipe != nil)
  }

  @Test func endingAKindThatIsNotRunningLeavesTheRunningOneAlone() async {
    let harness = await makeHarness()
    pointer.swipe(.began)
    await harness.settle()
    harness.manager.endDrag()
    harness.manager.slide = nil
    #expect(harness.manager.swipe != nil)
  }
}

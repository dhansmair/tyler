import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// A swipe acts on the display under the pointer, whichever display has focus: the laptop
/// (`main`: window 1 on workspace 1, window 2 on workspace 2) and the external display above it
/// (`secondary`: window 3 on workspace 5, window 4 on workspace 6).
@Suite("Several displays: swipes under the pointer")
@MainActor
struct SwipeUnderPointerScenarios {
  private let external = FakeDisplays.secondary
  private let overTheExternalDisplay = CGPoint(x: 1000, y: -700)
  private let pointer = FakePointer()
  private let clock = TestClock()

  private func onExternal(_ id: UInt32) -> WindowInfo {
    makeWindow(id: id, frame: CGRect(x: 100 + CGFloat(id) * 50, y: -1000, width: 300, height: 200))
  }

  private func harness(externalWindows: [UInt32] = [3, 4]) async -> ManagerHarness {
    let harness = ManagerHarness(
      [1, 2], extra: externalWindows.map(onExternal),
      displays: FakeDisplays(displays: [FakeDisplays.main, external]), pointer: pointer,
      clock: clock)
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.number(2), follow: false)
    if externalWindows == [3, 4] {
      await harness.osFocus(4)
      _ = harness.manager.moveToWorkspace(.number(6), follow: false)
    }
    await harness.osFocus(1)
    harness.backend.clearRecordedCalls()
    return harness
  }

  private func swipeToTheNext(in harness: ManagerHarness) async {
    for update in [SwipeUpdate.began, .moved(offset: -0.18), .ended(velocity: 0)] {
      pointer.swipe(update)
    }
    await harness.settle()
  }

  private func isParkedOnTheExternalDisplay(_ windowID: UInt32, _ harness: ManagerHarness) -> Bool {
    guard let frame = harness.frame(of: windowID) else { return false }
    return frame == Parking.frame(for: frame, on: external)
  }

  @Test func aSwipeOverTheExternalDisplaySwitchesTheExternalDisplaysWorkspaceAndFocusesIt() async {
    let harness = await harness()
    pointer.location = overTheExternalDisplay
    await swipeToTheNext(in: harness)

    #expect(harness.manager.rows.focusedKey == external.key)
    #expect(harness.manager.rows[1].number(at: harness.manager.rows[1].currentIndex) == 6)
    #expect(harness.frame(of: 4) == external.visibleFrame)
    #expect(isParkedOnTheExternalDisplay(3, harness))
    #expect(harness.manager.rows[0].currentIndex == 0, "the laptop stays on workspace 1")
    #expect(harness.frame(of: 1) == harness.area)
  }

  @Test func aSwipeOverTheLaptopActsThereWhileTheExternalDisplayHasFocus() async {
    let harness = await harness()
    await harness.osFocus(3)
    #expect(harness.manager.rows.focusedKey == external.key)

    await swipeToTheNext(in: harness)
    #expect(harness.manager.rows.focusedKey == FakeDisplays.main.key)
    #expect(harness.manager.rows[0].currentIndex == 1)
    #expect(harness.frame(of: 2) == harness.area)
    #expect(
      harness.frame(of: 3) == external.visibleFrame, "the external display stays on workspace 5")
  }

  @Test func aSwipeOverTheExternalDisplayScrollsItsStrip() async {
    let harness = await harness(externalWindows: [3, 4, 5])
    await harness.osFocus(3)
    _ = harness.manager.setLayout(.set(.strip))
    await harness.osFocus(1)
    let halves = TallLayout().frames(count: 2, in: external.visibleFrame)
    #expect(harness.frame(of: 3) == halves[0])

    pointer.location = overTheExternalDisplay
    await swipeToTheNext(in: harness)
    #expect(harness.manager.rows[1].current.firstVisible == WindowID(4))
    #expect(harness.frame(of: 4) == halves[0])
    #expect(harness.frame(of: 1) == harness.area, "the laptop doesn't move")
  }
}

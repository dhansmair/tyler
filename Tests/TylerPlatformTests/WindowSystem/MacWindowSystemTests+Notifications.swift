import ApplicationServices
import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerPlatform

@Suite("MacWindowSystem: an app's notifications")
@MainActor
struct MacWindowSystemNotificationsTests {
  private let harness = WindowSystemHarness()

  private func started(windows: [UInt32] = [1, 2]) async -> WindowSystemHarness {
    harness.addApp(100, windows: windows)
    await harness.start()
    _ = await harness.takeEvents()
    return harness
  }

  @Test func aNewWindowIsCreated() async {
    let harness = await started()
    harness.accessibility.addWindow(id: 3, frame: WindowSystemHarness.frame(of: 3), in: 100)
    harness.accessibility.post(kAXWindowCreatedNotification, for: 3, in: 100)
    #expect(await harness.takeEvents().created == [3])
    #expect(
      harness.accessibility.post(kAXMovedNotification, for: 3, in: 100),
      "the new window is observed")
  }

  @Test func aClosedWindowIsDestroyed() async {
    let harness = await started()
    harness.accessibility.removeWindow(1)
    harness.accessibility.post(kAXUIElementDestroyedNotification, for: 1, in: 100)
    #expect(await harness.takeEvents().destroyed == [1])
    #expect(harness.windowSystem.snapshot().map(\.id.rawValue) == [2])
  }

  @Test func aBurstOfMovesIsReadOnce() async {
    let harness = await started()
    let frame = CGRect(x: 700, y: 80, width: 400, height: 300)
    harness.accessibility.change(1, frame: frame)
    for _ in 0..<3 { harness.accessibility.post(kAXMovedNotification, for: 1, in: 100) }
    harness.accessibility.post(kAXResizedNotification, for: 1, in: 100)
    #expect(await harness.takeEvents().updated.map(\.frame) == [frame])
  }

  @Test func aMinimizedWindowIsReadBeforeTheMovesWaiting() async {
    let harness = await started()
    harness.accessibility.post(kAXMovedNotification, for: 1, in: 100)
    harness.accessibility.change(2, isMinimized: true)
    harness.accessibility.post(kAXWindowMiniaturizedNotification, for: 2, in: 100)
    let updated = await harness.takeEvents().updated
    #expect(updated.map(\.id.rawValue) == [2, 1])
    #expect(updated.first?.isMinimized == true)
  }

  @Test func aWindowThatCanNotBeReadIsNotUpdated() async {
    let harness = await started()
    harness.accessibility.answer(.cannotComplete, from: 1)
    harness.accessibility.post(kAXWindowMiniaturizedNotification, for: 1, in: 100)
    harness.accessibility.post(kAXMovedNotification, for: 1, in: 100)
    #expect(await harness.takeEvents().isEmpty)
  }

  @Test func theFocusFollowsTheApp() async {
    let harness = await started()
    harness.accessibility.post(kAXFocusedWindowChangedNotification, for: 2, in: 100)
    harness.accessibility.post(kAXFocusedWindowChangedNotification, for: 2, in: 100)
    #expect(await harness.takeEvents().focused == [2], "the same focus is reported once")
    #expect(harness.windowSystem.snapshot().map(\.isFocused) == [false, true])
  }

  @Test func anAppComingToTheFrontReportsItsFocusedWindow() async {
    let harness = await started()
    harness.accessibility.focus(1, in: 100)
    harness.workspace.activate(100)
    #expect(await harness.takeEvents().focused == [1])
  }

  @Test func theFocusOfAWindowNotSeenYetCreatesIt() async {
    let harness = await started()
    harness.accessibility.addWindow(id: 3, frame: WindowSystemHarness.frame(of: 3), in: 100)
    harness.accessibility.post(kAXFocusedWindowChangedNotification, for: 3, in: 100)
    let events = await harness.takeEvents()
    #expect(events.created == [3])
    #expect(events.focused == [3])
  }
}

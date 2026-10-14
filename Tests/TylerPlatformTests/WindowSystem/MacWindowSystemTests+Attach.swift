import Testing
import TylerCore
import TylerTestSupport

@testable import TylerPlatform

@Suite("MacWindowSystem: attaching to apps")
@MainActor
struct MacWindowSystemAttachTests {
  private let harness = WindowSystemHarness()

  @Test func theWindowsOfRegularAppsAreCreatedAtStart() async {
    harness.addApp(100, windows: [1, 2])
    harness.workspace.add(200, name: "Menu extra", policy: .accessory)
    harness.accessibility.addWindow(id: 3, frame: WindowSystemHarness.frame(of: 3), in: 200)
    harness.workspace.add(harness.workspace.ownProcessID, name: "tylerd")
    await harness.start()

    #expect(await harness.takeEvents().created == [1, 2])
    #expect(harness.windowSystem.snapshot().map(\.id.rawValue) == [1, 2])
    #expect(harness.windowSystem.snapshot().first?.appName == "App")
    #expect(!harness.accessibility.isObserving(200))
    #expect(!harness.accessibility.isObserving(harness.workspace.ownProcessID))
  }

  @Test func anAppLaunchedLaterIsAttached() async {
    await harness.start()
    harness.accessibility.addWindow(id: 5, frame: WindowSystemHarness.frame(of: 5), in: 300)
    harness.workspace.launch(300, name: "Later")
    #expect(await harness.takeEvents().created == [5])
  }

  @Test func anAppThatRefusesIsTriedAgain() async {
    harness.addApp(100, windows: [1])
    harness.accessibility.refuseObserving(100, times: 2)
    await harness.start()
    #expect(await harness.takeEvents().isEmpty)

    harness.clock.advance(by: .milliseconds(500))
    #expect(await harness.takeEvents().isEmpty, "the second attempt is refused too")
    harness.clock.advance(by: .milliseconds(500))
    #expect(await harness.takeEvents().created == [1])
  }

  @Test func anAppThatRefusesItsNotificationsIsNotHalfObserved() async {
    harness.addApp(100, windows: [1])
    harness.accessibility.answer(.cannotComplete, fromApp: 100)
    await harness.start()
    #expect(!harness.accessibility.isObserving(100))

    harness.accessibility.answer(nil, fromApp: 100)
    harness.clock.advance(by: .milliseconds(500))
    #expect(await harness.takeEvents().created == [1])
  }

  @Test func anAppGivenUpOnIsAttachedWhenItComesToTheFront() async {
    harness.addApp(100, windows: [1])
    harness.accessibility.refuseObserving(100, times: 6)
    await harness.start()
    for _ in 1..<6 {
      harness.clock.advance(by: .milliseconds(500))
      await settle()
    }
    #expect(!harness.clock.hasSleepers, "no seventh attempt")
    #expect(await harness.takeEvents().isEmpty)

    harness.workspace.activate(100)
    #expect(await harness.takeEvents().created == [1])
  }

  @Test func anAppAttachingWhileInFrontReportsItsFocusedWindow() async {
    harness.addApp(100, windows: [1, 2])
    harness.accessibility.focus(2, in: 100)
    harness.workspace.frontmostProcessID = 100
    await harness.start()
    #expect(await harness.takeEvents().focused == [2])
  }

  @Test func quittingDropsTheAppsWindows() async {
    harness.addApp(100, windows: [1, 2])
    harness.addApp(200, windows: [3])
    await harness.start()
    _ = await harness.takeEvents()

    harness.workspace.quit(100)
    #expect(await harness.takeEvents().destroyed.sorted() == [1, 2])
    #expect(harness.windowSystem.snapshot().map(\.id.rawValue) == [3])
    #expect(!harness.accessibility.isObserving(100))
  }

  @Test func stoppingForgetsEveryApp() async {
    harness.addApp(100, windows: [1])
    await harness.start()
    harness.windowSystem.stop()
    #expect(harness.windowSystem.snapshot().isEmpty)
    #expect(!harness.accessibility.isObserving(100))
  }
}

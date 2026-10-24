import Testing
import TylerCore
import TylerTestSupport

@testable import TylerPlatform

@Suite("MacWindowSystem: reading every window again")
@MainActor
struct MacWindowSystemFreshWindowsTests {
  private let harness = WindowSystemHarness()

  @Test func saysWhatTheWindowSystemMissed() async {
    harness.addApp(100, windows: [1])
    harness.addApp(200, name: "Busy", windows: [3])
    harness.accessibility.refuseObserving(200, times: 1)
    await harness.start()
    harness.accessibility.addWindow(id: 2, frame: WindowSystemHarness.frame(of: 2), in: 100)
    harness.accessibility.focus(2, in: 100)
    harness.workspace.frontmostProcessID = 100

    let fresh = harness.windowSystem.freshWindows()
    #expect(fresh.tracked.map(\.id.rawValue) == [1])
    #expect(fresh.untracked.map(\.id.rawValue) == [2])
    #expect(fresh.unattachedApps == ["Busy"])
    #expect(fresh.focusedID == WindowID(2))
  }

  @Test func tracksTheWindowsItMissed() async {
    harness.addApp(100, windows: [1])
    await harness.start()
    _ = await harness.takeEvents()
    harness.accessibility.addWindow(id: 2, frame: WindowSystemHarness.frame(of: 2), in: 100)

    harness.windowSystem.trackUntrackedWindows()
    #expect(await harness.takeEvents().created == [2])
    #expect(harness.windowSystem.snapshot().map(\.id.rawValue) == [1, 2])
    harness.windowSystem.trackUntrackedWindows()
    #expect(await harness.takeEvents().created.isEmpty, "a tracked window is left alone")
  }
}

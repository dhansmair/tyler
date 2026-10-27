import Testing
import TylerTestSupport

@testable import TylerServer

/// A workspace that comes into view because the focus moved says so in the log, so a switch
/// nobody asked for can be traced to the window that took the focus (#71).
@Suite("Workspaces: the log of a focus-driven switch")
@MainActor
struct FocusSwitchLogScenarios {
  @Test func aSwitchNamesTheWorkspaceTheDisplayAndTheWindow() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary],
      workspaces: [1: [1], 5: [2], 6: [3]])
    await scenario.command("config set log.level info")
    await scenario.focus(3)
    #expect(scenario.shown == [1, 6])
    #expect(scenario.logged("workspace switching - 6 on display 2 - focus moved to #3 (App)"))
  }

  @Test func aFocusOnTheWorkspaceInViewSwitchesNothing() async {
    let scenario = await Scenario(workspaces: [1: [1, 2], 2: [3]])
    await scenario.command("config set log.level debug")
    await scenario.focus(2)
    #expect(scenario.logged("window focused - #2 (App) - not tylerd's own"))
    #expect(!scenario.logLines.contains { $0.contains("workspace switching") })
  }

  @Test func eachFocusReadSaysWhetherItWasTylerdsOwn() async {
    let scenario = await Scenario(workspaces: [1: [1], 2: [2]])
    await scenario.command("config set log.level debug")
    await scenario.command("workspace focus next")  // tylerd focuses window 2
    await scenario.focus(2)
    await scenario.focus(1)
    #expect(scenario.logged("window focused - #2 (App) - tylerd's own focus coming back"))
    #expect(scenario.logged("window focused - #1 (App) - not tylerd's own"))
    #expect(scenario.logged("workspace switching - 1 on display 1 - focus moved to #1 (App)"))
  }
}

import Testing
import TylerCore
import TylerProtocol

@testable import TylerServer

/// `tyler window close`: the focused window closes, as with its close button, and the rest of
/// its workspace retiles once the app reports it gone.
@Suite("Tiling: tyler window close")
@MainActor
struct CloseWindowScenarios {
  @Test func theFocusedWindowClosesAndTheRestRetile() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(2)
    #expect(await scenario.command("window close") == .ok)
    #expect(scenario.harness.windowSystem.closeCalls == [WindowID(2)])
    #expect(scenario.list(1) == [1, 3])
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
    #expect(scenario.frame(of: 3) == scenario.rect(.rightHalf))
  }

  @Test func withoutAFocusedWindowNothingCloses() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    #expect(await scenario.command("window close") == .error("no focused window"))
    #expect(scenario.harness.windowSystem.closeCalls.isEmpty)
  }

  @Test func closingWorksWithTilingOff() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.command("tiling off")
    await scenario.focus(2)
    #expect(await scenario.command("window close") == .ok)
    #expect(scenario.harness.windowSystem.closeCalls == [WindowID(2)])
  }

  @Test func aWindowThatRefusesStaysInItsList() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    scenario.harness.windowSystem.failingClose = [WindowID(2)]
    await scenario.focus(2)
    #expect(
      await scenario.command("window close")
        == .error("cannot close window 2: fake refusal"))
    #expect(scenario.list(1) == [1, 2])
  }
}

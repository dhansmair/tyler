import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// A window tiled again with `window float off` going back to the place in the list it left.
/// Tall with windows 1, 2 and 3.
@Suite("Tiling: back to its place after floating")
@MainActor
struct FloatPlaceScenarios {
  private func scenario() async -> Scenario {
    await Scenario(workspaces: [1: [1, 2, 3]], layout: .tall)
  }

  @Test func theMainWindowTiledAgainIsTheMainWindowAgain() async {
    let scenario = await scenario()
    await scenario.focus(1)
    await scenario.command("window float on")
    #expect(scenario.list(1) == [2, 3])

    await scenario.command("window float off")

    #expect(scenario.list(1) == [1, 2, 3])
    #expect(scenario.frame(of: 1) == scenario.rect(.leftHalf))
  }

  @Test func aPlacePastTheEndOfTheListPutsTheWindowLast() async {
    let scenario = await scenario()
    await scenario.focus(3)
    await scenario.command("window float on")
    await scenario.focus(2)
    await scenario.command("window close")
    scenario.harness.windowSystem.windows.removeAll { $0.id == WindowID(2) }
    scenario.harness.windowSystem.send(.destroyed(WindowID(2)))
    await scenario.runUntilQuiet()
    await scenario.focus(3)

    await scenario.command("window float off")

    #expect(scenario.list(1) == [1, 3])
  }

  @Test func aMinimizedWindowLetGoGoesBackToItsPlaceWhenRestored() async {
    let scenario = await scenario()
    await scenario.focus(1)
    await scenario.command("window float on")
    let windowSystem = scenario.harness.windowSystem
    windowSystem.send(.updated(makeWindow(id: 1, isMinimized: true, isFocused: true)))
    await scenario.runUntilQuiet()

    await scenario.command("window float off")
    #expect(scenario.list(1) == [2, 3])
    windowSystem.send(.updated(makeWindow(id: 1, isFocused: true)))
    await scenario.runUntilQuiet()

    #expect(scenario.list(1) == [1, 2, 3])
  }
}

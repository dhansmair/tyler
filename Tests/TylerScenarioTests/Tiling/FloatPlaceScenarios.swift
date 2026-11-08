import CoreGraphics
import Testing
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

  /// A slot number would drift here: 2 floated from slot 2 would come back after 3.
  @Test func itKeepsItsPlaceWhenAWindowBeforeItCloses() async {
    let scenario = await scenario()
    await scenario.focus(2)
    await scenario.command("window float on")
    await scenario.close(1)
    await scenario.focus(2)

    await scenario.command("window float off")

    #expect(scenario.list(1) == [2, 3])
  }

  @Test func aWindowTiledAgainIsTheOneSwapAndFocusAreRelativeTo() async {
    let scenario = await scenario()
    await scenario.focus(2)
    await scenario.command("window float on")
    await scenario.command("window float off")

    await scenario.command("window swap next")

    #expect(scenario.list(1) == [1, 3, 2])
  }

  @Test(arguments: ["window swap next", "window swap master", "window promote", "window demote"])
  func aCommandOnTheFocusedWindowsPlaceDoesNothingWhileItFloats(command: String) async {
    let scenario = await scenario()
    await scenario.focus(2)
    await scenario.command("window float on")

    let response = await scenario.command(command)

    #expect(response == .message("the focused window floats"))
    #expect(scenario.list(1) == [1, 3])
  }

  @Test func itKeepsItsPlaceAcrossARestart() async {
    let scenario = await scenario()
    await scenario.focus(1)
    await scenario.command("window float on")
    let next = await scenario.restart()
    await next.focus(1)

    await next.command("window float off")

    #expect(next.list(1) == [1, 2, 3])
  }
}

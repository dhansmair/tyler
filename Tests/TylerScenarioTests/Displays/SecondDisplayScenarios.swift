import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

/// With a second display connected, everything still happens on the primary one: its area, its
/// parking spot, its slides and its resizing. These pin that windows on the primary display behave
/// as with one display.
@Suite("Two displays: the primary display's workspaces")
@MainActor
struct SecondDisplayScenarios {
  private let displays = [FakeDisplays.main, FakeDisplays.secondary]

  @Test func theIndicatorShowsThePrimaryDisplaysArea() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]), displays: displays)
    #expect(scenario.indicator.shown.last?.area == scenario.rect(.full))
  }

  @Test func aWindowOpeningOnAnotherWorkspaceParksAtThePrimaryDisplaysEdge() async {
    let scenario = await Scenario(
      displays: displays, workspaces: [1: [1]],
      config: Config(apps: ["firefox": Config.App(workspace: 3)]))
    var firefox = makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))
    firefox.appName = "Firefox"
    await scenario.open(firefox)

    #expect(scenario.workspaces[9] == 3)
    #expect(scenario.frame(of: 9)?.minX == scenario.rect(.full).maxX - 1)
  }

  @Test func aSwipeSlidesThePrimaryDisplaysWorkspaces() async {
    let scenario = await Scenario(displays: displays, workspaces: [1: [1], 2: [2]])
    await scenario.swipe(.left)
    #expect(scenario.shown == [2, 5])
    #expect(scenario.frame(of: 2) == scenario.rect(.full))
    #expect(scenario.frame(of: 1)?.minX == scenario.rect(.full).maxX - 1)
  }

  @Test func resizingWithTheMouseLaysOutInThePrimaryDisplaysArea() async {
    let scenario = await Scenario(displays: displays, workspaces: [1: [1, 2, 3]])
    scenario.pointer.isPrimaryButtonDown = true
    await scenario.moveByHand(1, to: CGRect(x: 55, y: 38, width: 1047, height: 1131))
    #expect(scenario.frame(of: 2) == CGRect(x: 1102, y: 38, width: 698, height: 566))
    scenario.pointer.release()
    await scenario.runUntilQuiet()
    #expect(scenario.frame(of: 3) == CGRect(x: 1102, y: 604, width: 698, height: 565))
  }
}

import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@Suite("Layout notice")
@MainActor
struct LayoutNoticeScenarios {
  @Test func settingALayoutNamesIt() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])

    _ = scenario.harness.manager.setLayout(.set(.grid))

    #expect(scenario.layoutNotice.shown.map(\.name) == ["grid"])
  }

  @Test func cyclingNamesTheLayoutItReaches() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])

    _ = scenario.harness.manager.setLayout(.next)

    #expect(scenario.layoutNotice.shown.map(\.name) == ["grid"])
  }

  @Test func settingTheLayoutAlreadySetNamesItToo() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])

    _ = scenario.harness.manager.setLayout(.set(.tall))

    #expect(scenario.layoutNotice.shown.map(\.name) == ["tall"])
  }

  @Test func aRefusedCommandShowsNothing() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    _ = scenario.harness.manager.setTiling(.off)

    _ = scenario.harness.manager.setLayout(.next)

    #expect(scenario.layoutNotice.shown.isEmpty)
  }

  @Test func showsOnTheFocusedDisplay() async {
    let right = DisplayInfo(
      id: 2, frame: CGRect(x: 1800, y: 0, width: 1920, height: 1080),
      visibleFrame: CGRect(x: 1800, y: 30, width: 1920, height: 1050))
    let scenario = await Scenario(
      displays: [FakeDisplays.main, right], workspaces: [1: [1], 5: [2]], showing: [1, 5])

    _ = scenario.harness.manager.switchWorkspace(.number(5))
    _ = scenario.harness.manager.setLayout(.set(.full))

    #expect(scenario.layoutNotice.shown.map(\.area) == [right.visibleFrame])
  }

  @Test func theConfigCanTurnItOff() async {
    var config = Config()
    config.layouts.showsNotice = false
    let scenario = await Scenario(workspaces: [1: [1, 2]], config: config)

    _ = scenario.harness.manager.setLayout(.set(.grid))

    #expect(scenario.layoutNotice.shown.isEmpty)
  }

  @Test func switchingWorkspaceShowsNothing() async {
    let scenario = await Scenario(workspaces: [1: [1], 2: [2]])

    _ = scenario.harness.manager.switchWorkspace(.number(2))

    #expect(scenario.layoutNotice.shown.isEmpty)
  }
}

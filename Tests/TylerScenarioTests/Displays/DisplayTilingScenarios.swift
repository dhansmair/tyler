import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

/// Tiling every display: the laptop (`main`, workspaces 1 to 4) and the external display above it
/// (`secondary`, workspaces 5 to 8). Windows 1 and 2 start on the laptop, 3 on the external
/// display.
@Suite("Several displays: tiling each one")
@MainActor
struct DisplayTilingScenarios {
  private let firefoxFrame = CGRect(x: 700, y: 100, width: 300, height: 200)

  private func scenario(config: Config = Config()) async -> Scenario {
    await Scenario(
      openAtStart: spread([1, 2])
        + [makeWindow(id: 3, frame: CGRect(x: 100, y: -1000, width: 300, height: 200))],
      displays: [FakeDisplays.main, FakeDisplays.secondary], config: config)
  }

  private func firefox() -> WindowInfo {
    var firefox = makeWindow(id: 9, frame: firefoxFrame)
    firefox.appName = "Firefox"
    return firefox
  }

  @Test func eachDisplayTilesItsCurrentWorkspace() async {
    let scenario = await scenario()
    #expect(scenario.workspaces == [1: 1, 2: 1, 3: 5])
    #expect(
      [scenario.frame(of: 1), scenario.frame(of: 2)]
        == [scenario.rect(.leftHalf), scenario.rect(.rightHalf)])
    #expect(scenario.frame(of: 3) == scenario.rect(.full, display: 2))
  }

  @Test func listShowsEachWindowsDisplayAndWorkspaceNumber() async {
    let listed = await scenario().windowList
    let byID = Dictionary(uniqueKeysWithValues: listed.map { ($0.id.rawValue, $0) })
    #expect(byID[1]?.displayNumber == 1)
    #expect(byID[3]?.displayNumber == 2)
    #expect(byID[3]?.workspace == 5)
    #expect(byID[3]?.slot == 1)
  }

  @Test func aWindowAssignedToAHiddenWorkspaceOfTheExternalDisplayParksAtItsEdge() async {
    let scenario = await scenario(config: Config(apps: ["firefox": Config.App(workspace: 6)]))
    await scenario.open(firefox())

    #expect(scenario.workspaces[9] == 6)
    #expect(scenario.frame(of: 9)?.minX == scenario.rect(.full, display: 2).maxX - 1)
    #expect(scenario.frame(of: 3) == scenario.rect(.full, display: 2), "workspace 5 stays")
  }

  @Test func tilingOffBringsBackTheParkedWindowsOfEveryDisplay() async {
    let scenario = await scenario(config: Config(apps: ["firefox": Config.App(workspace: 6)]))
    await scenario.open(firefox())

    #expect(await scenario.command("tiling off") == .message("tiling off"))
    #expect(scenario.frame(of: 9) == firefoxFrame)
    #expect(scenario.workspaces[9] == nil)
  }

  @Test func withADisplayToTheRightTheLaptopParksAtItsLeftEdge() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.right], workspaces: [1: [1, 2]])
    await scenario.command("workspace focus next")
    for id: UInt32 in [1, 2] {
      #expect(scenario.frame(of: id)?.maxX == scenario.rect(.full).minX + 1)
    }
  }

  @Test func aRestartKeepsTheWorkspacesOfEveryDisplay() async {
    let scenario = await scenario()
    scenario.windowSystem.clearRecordedCalls()
    let next = await scenario.restart()
    #expect(next.workspaces == [1: 1, 2: 1, 3: 5])
    #expect(next.windowSystem.moves.isEmpty, "every window is already where it belongs")
  }

  @Test func aRestartWithTheExternalDisplayUnpluggedKeepsItsWorkspacesWaiting() async {
    let scenario = await scenario()
    await scenario.changeDisplays(to: [FakeDisplays.main])
    let next = await scenario.restart()
    #expect(next.workspaces == [1: 1, 2: 1, 3: 5])
    await next.changeDisplays(to: [FakeDisplays.main, FakeDisplays.secondary])
    #expect(next.shown == [1, 5])
    #expect(!next.isParked(3), "workspace 5 is back on the external display")
  }
}

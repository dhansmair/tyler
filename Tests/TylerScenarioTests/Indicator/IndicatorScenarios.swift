import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerProtocol
import TylerTestSupport

@testable import TylerServer

@Suite("Indicator updates")
@MainActor
struct IndicatorScenarios {
  private func scenario(
    config: Config = Config(), configFile: FakeConfigFile? = nil, isTrusted: Bool = true
  ) async -> Scenario {
    await Scenario(
      openAtStart: spread([1, 2]), config: config, configFile: configFile,
      gate: FakeGate(isTrusted: isTrusted))
  }

  @Test func itShowsTheStateFromTheStartAndWhenPermissionArrives() async {
    let scenario = await scenario(isTrusted: false)
    #expect(scenario.indicator.shown.count == 1)
    #expect(scenario.indicator.shown.last?.tiling == .waitingForPermission)
    await scenario.grantPermission()
    let last = scenario.indicator.shown.last
    #expect(last?.tiling == .on)
    #expect(last?.row.currentIndex == 0)
    #expect(last?.row.count == 4)
    #expect(last?.row[0].count == 2)
  }

  @Test func itFollowsSwitchesLayoutsAndTiling() async {
    let scenario = await scenario()
    await scenario.command("workspace focus 3")
    #expect(scenario.indicator.shown.last?.row.currentIndex == 2)
    await scenario.command("layout next")
    #expect(scenario.indicator.shown.last?.row.current.layout == .grid)
    await scenario.command("tiling off")
    #expect(scenario.indicator.shown.last?.tiling == .off)
  }

  @Test func itCountsWindowsThatOpenAndClose() async {
    let scenario = await scenario()
    await scenario.open(makeWindow(id: 9))
    #expect(scenario.indicator.shown.last?.row[0].count == 3)
    await scenario.close(1)
    #expect(scenario.indicator.shown.last?.row[0].count == 2)
  }

  @Test func itIsToldAboutFocusButNotAboutNothing() async {
    let scenario = await scenario()
    await scenario.command("window focus next")
    await scenario.focus(2)
    #expect(scenario.indicator.shown.last?.row.current.focused == WindowID(2))
    let count = scenario.indicator.shown.count
    await scenario.focus(2)
    await scenario.command("workspace focus 1")
    #expect(scenario.indicator.shown.count == count)
  }

  @Test func reloadingTheConfigReachesTheIndicators() async {
    let textOff = Config.Indicators(text: .init(isEnabled: false))
    let scenario = await scenario(configFile: FakeConfigFile(.config(Config(indicators: textOff))))
    #expect(scenario.indicator.shown.last?.settings.text.isEnabled == true)
    await scenario.command("config reload")
    #expect(scenario.indicator.shown.last?.settings == textOff)
  }

  @Test func settingTheConfigReachesTheIndicators() async {
    let scenario = await scenario(isTrusted: false)
    await scenario.command("config set indicators.map.enabled false")
    #expect(
      scenario.indicator.shown.last?.settings == Config.Indicators(map: .init(isEnabled: false)))
    await scenario.command("config set apps.App.icon terminal")
    await scenario.grantPermission()
    #expect(
      scenario.indicator.shown.last?.apps.values.map(\.icon)
        == [.symbol("terminal"), .symbol("terminal")])
  }

  @Test func theSnapshotHoldsEachTiledWindowsApp() async {
    let scenario = await scenario()
    let expected = Dictionary(
      uniqueKeysWithValues: scenario.windowSystem.windows.map {
        (
          $0.id,
          IndicatorSnapshot.App(processID: $0.processID, name: $0.appName, bundleID: $0.bundleID)
        )
      })
    #expect(scenario.indicator.shown.last?.apps == expected)
  }

  @Test func theSnapshotHoldsTheIconTheConfigFileSetsForAnApp() async {
    let scenario = await scenario(
      config: Config(apps: ["app": Config.App(icon: .symbol("terminal"))]))
    #expect(
      scenario.indicator.shown.last?.apps.values.map(\.icon)
        == [.symbol("terminal"), .symbol("terminal")])
  }

  @Test func theSnapshotHoldsTheDisplaysArea() async {
    let scenario = await scenario(isTrusted: false)
    #expect(scenario.indicator.shown.last?.area == FakeDisplays.main.visibleFrame)
  }

  @Test func itShowsTheFocusedDisplaysRowAndFollowsFocusToTheExternalDisplay() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: [1, 2], 5: [3]])

    await scenario.focus(3)
    var last = scenario.indicator.shown.last
    #expect(last?.row.numbers == [5, 6, 7, 8])
    #expect(last?.row.current.windows == [WindowID(3)])
    #expect(last?.area == FakeDisplays.secondary.visibleFrame)

    await scenario.focus(1)
    last = scenario.indicator.shown.last
    #expect(last?.row.numbers == [1, 2, 3, 4])
    #expect(last?.area == FakeDisplays.main.visibleFrame)
  }
}

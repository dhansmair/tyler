import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

/// `tyler config get` and `set`: reading the live config, and changing one setting until tylerd
/// stops or the config is reloaded.
@Suite("Config get and set")
@MainActor
struct ConfigGetSetScenarios {
  private let file = FakeConfigFile(.config(Config()))

  private func scenario(config: Config = Config()) async -> Scenario {
    await Scenario(workspaces: [1: [1, 2]], config: config, configFile: file)
  }

  private static let until = "(until tylerd stops or `tyler config reload`)"
  private static let stays = "(the current settings stay)"

  @Test func settingTheGapsRetilesAtOnce() async {
    let scenario = await scenario()
    #expect(
      await scenario.command("config set gaps.inner 8")
        == .message("gaps.inner = 8 \(Self.until)"))
    let expected = TallLayout().frames(
      count: 2, in: scenario.rect(.full), gaps: LayoutGaps(Config.Gaps(inner: 8)))
    #expect([1, 2].compactMap(scenario.frame(of:)) == expected)
  }

  @Test func theLogLevelTakesEffectAndAReloadPutsItBack() async {
    let scenario = await scenario()
    #expect(scenario.logLevel == .warning)
    await scenario.command("config set log.level debug")
    #expect(scenario.logLevel == .debug)
    await scenario.command("config reload")
    #expect(scenario.logLevel == .warning)
  }

  @Test func aWordWithoutQuotesIsAString() async {
    let scenario = await scenario()
    #expect(
      await scenario.command("config set layouts.default strip")
        == .message("layouts.default = \"strip\" \(Self.until)"))
    #expect(scenario.config?.layouts.initial == .strip)
  }

  @Test(arguments: [
    ("gaps.inner", "-1", "gaps.inner must be a whole number of points, 0 or more"),
    ("gaps.middle", "3", "unknown setting 'gaps.middle' (use inner or outer)"),
    ("colours.inner", "3", "unknown setting 'colours'"),
    ("gaps.inner.x", "3", "gaps.inner is a value, not a table of settings"),
    ("gaps", "3", "gaps must be a table: write [gaps] and put inner and outer below it"),
    (
      "layouts.cycle", "[\"tall\"",
      "'[\"tall\"' is not a value: an array must close on the same line"
    ),
    ("gaps.", "3", "'gaps.' is not the name of a setting: expected a key"),
  ])
  func aSettingThatCantBeUsedChangesNothing(name: String, value: String, message: String) async {
    let scenario = await scenario()
    let frames = [1, 2].compactMap(scenario.frame(of:))
    #expect(
      await scenario.command("config set \(name) \(value)") == .error("\(message) \(Self.stays)"))
    #expect(scenario.config == Config())
    #expect(scenario.changedSettings.isEmpty)
    #expect([1, 2].compactMap(scenario.frame(of:)) == frames)
  }

  @Test func anAppsWorkspaceIsCheckedAgainstTheDisplaysLists() async {
    let scenario = await scenario(config: Config(displays: [1: [1, 2]]))
    #expect(
      await scenario.command("config set apps.Firefox.workspace 7")
        == .error("apps.firefox.workspace = 7, but no display lists workspace 7 \(Self.stays)"))
    #expect(await scenario.command("config set apps.Firefox.workspace 2") != .error(""))
    #expect(scenario.config?.apps == ["firefox": Config.App(workspace: 2)])
  }

  @Test func settingAnAppByAnotherCaseChangesItsTable() async {
    let scenario = await scenario(config: Config(apps: ["firefox": Config.App(workspace: 2)]))
    await scenario.command("config set apps.FIREFOX.icon globe")
    #expect(
      scenario.config?.apps == ["firefox": Config.App(workspace: 2, icon: .symbol("globe"))])
    await scenario.command("config set apps.\"org.mozilla.firefox\".workspace 3")
    #expect(scenario.config?.apps["org.mozilla.firefox"] == Config.App(workspace: 3))
  }

  @Test func aNewWorkspaceCountTakesEffectAtOnce() async {
    let scenario = await scenario()
    await scenario.command("config set workspaces.count 2")
    #expect(scenario.rows == [[1, 2]])
  }

  @Test func thePointerFollowsTheGestureSettings() async {
    let scenario = await scenario()
    #expect(scenario.pointer.swipeFingers == 3)
    await scenario.command("config set gestures.fingers 4")
    #expect(scenario.pointer.swipeFingers == 4)
    await scenario.command("config set gestures.swipe false")
    #expect(scenario.pointer.swipeFingers == nil)
  }

  @Test func reloadDropsWhatSetChanged() async {
    let scenario = await scenario()
    await scenario.command("config set gaps.inner 8")
    await scenario.command("config set gaps.outer 4")
    await scenario.command("config set gaps.inner 9")
    #expect(scenario.changedSettings == ["gaps.inner", "gaps.outer"])
    await scenario.command("config reload")
    #expect(scenario.config == Config())
    #expect(scenario.changedSettings.isEmpty)
  }

  @Test func aReloadThatFailsKeepsWhatSetChanged() async {
    let scenario = await scenario()
    await scenario.command("config set gaps.inner 8")
    file.write(.broken(.invalid("boom")))
    await scenario.command("config reload")
    #expect(scenario.config?.gaps.inner == 8)
    #expect(scenario.changedSettings == ["gaps.inner"])
  }

  @Test(arguments: [
    ("gaps.inner", "8"),
    ("gaps", "[gaps]\ninner = 8\nouter = 0"),
    ("layouts.cycle", "[\"tall\", \"grid\", \"full\"]"),
    ("indicators.map.enabled", "true"),
    ("apps.FIREFOX.icon", "\"globe\""),
    ("apps.firefox", "[apps.firefox]\nicon = \"globe\""),
  ])
  func getShowsASettingOrATableAsTheFileWritesIt(name: String, shown: String) async {
    let config = Config(
      gaps: Config.Gaps(inner: 8), apps: ["firefox": Config.App(icon: .symbol("globe"))])
    #expect(await scenario(config: config).command("config get \(name)") == .message(shown))
  }

  @Test func getWithoutANameShowsTheWholeConfig() async throws {
    let config = Config(gaps: Config.Gaps(inner: 8))
    guard case .message(let text) = await scenario(config: config).command("config get") else {
      Issue.record("no message")
      return
    }
    #expect(try Config.parse(text) == config)
  }

  @Test(arguments: [
    ("apps.firefox.workspace", "apps.firefox.workspace is not set"),
    ("apps.slack", "apps.slack is not set"),
    ("displays.2.workspaces", "displays.2.workspaces is not set"),
    ("gaps.middle", "unknown setting 'gaps.middle' (`tyler config get` lists every setting)"),
    ("gaps.inner.x", "unknown setting 'gaps.inner.x' (`tyler config get` lists every setting)"),
  ])
  func getSaysWhetherAMissingSettingExists(name: String, message: String) async {
    let config = Config(apps: ["firefox": Config.App(icon: .symbol("globe"))])
    #expect(await scenario(config: config).command("config get \(name)") == .error(message))
  }
}

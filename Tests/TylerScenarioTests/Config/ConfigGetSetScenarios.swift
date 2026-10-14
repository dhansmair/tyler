import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// `tyler config get` and `set`: reading the live config, and changing one setting until tylerd
/// stops or the config is reloaded.
@Suite("Config get and set")
@MainActor
struct ConfigGetSetScenarios {
  private let file = FakeConfigFile(.config(Config()))

  private func harness(config: Config = Config(), pointer: FakePointer? = nil) -> ManagerHarness {
    ManagerHarness([1, 2], config: config, configFile: file, pointer: pointer)
  }

  private static let until = "(until tylerd stops or `tyler config reload`)"
  private static let stays = "(the current settings stay)"

  @Test func settingTheGapsRetilesAtOnce() {
    let harness = harness()
    #expect(
      harness.manager.setConfig("gaps.inner", to: "8") == .message("gaps.inner = 8 \(Self.until)"))
    let expected = TallLayout().frames(
      count: 2, in: harness.area, gaps: LayoutGaps(Config.Gaps(inner: 8)))
    #expect([1, 2].compactMap(harness.frame(of:)) == expected)
  }

  @Test func theLogLevelTakesEffectAndAReloadPutsItBack() {
    let harness = harness()
    #expect(harness.manager.logOutput.level == .warning)
    _ = harness.manager.setConfig("log.level", to: "debug")
    #expect(harness.manager.logOutput.level == .debug)
    _ = harness.manager.reload()
    #expect(harness.manager.logOutput.level == .warning)
  }

  @Test func aWordWithoutQuotesIsAString() {
    let harness = harness()
    #expect(
      harness.manager.setConfig("layouts.default", to: "strip")
        == .message("layouts.default = \"strip\" \(Self.until)"))
    #expect(harness.manager.config.layouts.initial == .strip)
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
  func aSettingThatCantBeUsedChangesNothing(name: String, value: String, message: String) {
    let harness = harness()
    let frames = [1, 2].compactMap(harness.frame(of:))
    #expect(harness.manager.setConfig(name, to: value) == .error("\(message) \(Self.stays)"))
    #expect(harness.manager.config == Config())
    #expect(harness.manager.configChanges.isEmpty)
    #expect([1, 2].compactMap(harness.frame(of:)) == frames)
  }

  @Test func anAppsWorkspaceIsCheckedAgainstTheDisplaysLists() {
    let harness = harness(config: Config(displays: [1: [1, 2]]))
    #expect(
      harness.manager.setConfig("apps.Firefox.workspace", to: "7")
        == .error("apps.firefox.workspace = 7, but no display lists workspace 7 \(Self.stays)"))
    #expect(harness.manager.setConfig("apps.Firefox.workspace", to: "2") != .error(""))
    #expect(harness.manager.config.apps == ["firefox": Config.App(workspace: 2)])
  }

  @Test func settingAnAppByAnotherCaseChangesItsTable() {
    let harness = harness(config: Config(apps: ["firefox": Config.App(workspace: 2)]))
    _ = harness.manager.setConfig("apps.FIREFOX.icon", to: "globe")
    #expect(
      harness.manager.config.apps == ["firefox": Config.App(workspace: 2, icon: .symbol("globe"))])
    _ = harness.manager.setConfig("apps.\"org.mozilla.firefox\".workspace", to: "3")
    #expect(harness.manager.config.apps["org.mozilla.firefox"] == Config.App(workspace: 3))
  }

  @Test func aNewWorkspaceCountTakesEffectAtOnce() {
    let harness = harness()
    _ = harness.manager.setConfig("workspaces.count", to: "2")
    #expect(harness.manager.workspaces.count == 2)
  }

  @Test func thePointerFollowsTheGestureSettings() {
    let pointer = FakePointer()
    let harness = harness(pointer: pointer)
    #expect(pointer.swipeFingers == 3)
    _ = harness.manager.setConfig("gestures.fingers", to: "4")
    #expect(pointer.swipeFingers == 4)
    _ = harness.manager.setConfig("gestures.swipe", to: "false")
    #expect(pointer.swipeFingers == nil)
  }

  @Test func reloadDropsWhatSetChanged() {
    let harness = harness()
    _ = harness.manager.setConfig("gaps.inner", to: "8")
    _ = harness.manager.setConfig("gaps.outer", to: "4")
    _ = harness.manager.setConfig("gaps.inner", to: "9")
    #expect(harness.manager.configChanges == ["gaps.inner", "gaps.outer"])
    _ = harness.manager.reload()
    #expect(harness.manager.config == Config())
    #expect(harness.manager.configChanges.isEmpty)
  }

  @Test func aReloadThatFailsKeepsWhatSetChanged() {
    let harness = harness()
    _ = harness.manager.setConfig("gaps.inner", to: "8")
    file.write(.broken(.invalid("boom")))
    _ = harness.manager.reload()
    #expect(harness.manager.config.gaps.inner == 8)
    #expect(harness.manager.configChanges == ["gaps.inner"])
  }

  @Test(arguments: [
    ("gaps.inner", "8"),
    ("gaps", "[gaps]\ninner = 8\nouter = 0"),
    ("layouts.cycle", "[\"tall\", \"full\"]"),
    ("indicators.map.enabled", "true"),
    ("apps.FIREFOX.icon", "\"globe\""),
    ("apps.firefox", "[apps.firefox]\nicon = \"globe\""),
  ])
  func getShowsASettingOrATableAsTheFileWritesIt(name: String, shown: String) {
    let config = Config(
      gaps: Config.Gaps(inner: 8), apps: ["firefox": Config.App(icon: .symbol("globe"))])
    #expect(harness(config: config).manager.configValue(name) == .message(shown))
  }

  @Test func getWithoutANameShowsTheWholeConfig() throws {
    let manager = harness(config: Config(gaps: Config.Gaps(inner: 8))).manager
    guard case .message(let text) = manager.configValue(nil) else {
      Issue.record("no message")
      return
    }
    #expect(try Config.parse(text) == manager.config)
  }

  @Test(arguments: [
    ("apps.firefox.workspace", "apps.firefox.workspace is not set"),
    ("apps.slack", "apps.slack is not set"),
    ("displays.2.workspaces", "displays.2.workspaces is not set"),
    ("gaps.middle", "unknown setting 'gaps.middle' (`tyler config get` lists every setting)"),
    ("gaps.inner.x", "unknown setting 'gaps.inner.x' (`tyler config get` lists every setting)"),
  ])
  func getSaysWhetherAMissingSettingExists(name: String, message: String) {
    let config = Config(apps: ["firefox": Config.App(icon: .symbol("globe"))])
    #expect(harness(config: config).manager.configValue(name) == .error(message))
  }
}

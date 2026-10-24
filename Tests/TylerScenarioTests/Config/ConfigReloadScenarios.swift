import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

/// The config at startup and `reload`, driven through a fake window system and a fake config file.
@Suite("Config and reload")
@MainActor
struct ConfigReloadScenarios {
  private let area = FakeDisplays.main.visibleFrame
  private let gaps = Config(gaps: Config.Gaps(inner: 8, outer: 12))

  private func scenario(
    config: Config = Config(), file: FakeConfigFile? = FakeConfigFile(), isTrusted: Bool = true
  ) async -> Scenario {
    await Scenario(
      openAtStart: spread([1, 2]), config: config, configFile: file,
      gate: FakeGate(isTrusted: isTrusted))
  }

  /// Where the tall layout puts windows 1 and 2 with these settings.
  private func expectedFrames(_ config: Config, mainRatio: Double = 0.5) -> [CGRect] {
    TallLayout().frames(
      count: 2, in: area, state: TallLayoutState(mainRatio: mainRatio),
      gaps: LayoutGaps(config.gaps))
  }

  /// Where the tall layout puts a workspace's only window with these settings.
  private func oneWindowFrame(_ config: Config) -> CGRect? {
    TallLayout().frames(count: 1, in: area, gaps: LayoutGaps(config.gaps)).first
  }

  private func frames(_ scenario: Scenario) -> [CGRect] {
    [1, 2].compactMap { scenario.frame(of: $0) }
  }

  @Test func theConfigGivenAtStartIsUsedForTheFirstTiling() async {
    let scenario = await scenario(config: gaps)
    #expect(scenario.config == gaps)
    #expect(frames(scenario) == expectedFrames(gaps))
  }

  @Test func reloadAppliesNewGapsAndRetilesAtOnce() async {
    let file = FakeConfigFile()
    let scenario = await scenario(file: file)
    file.write(.config(gaps))

    #expect(await scenario.command("config reload") == .message("reloaded \(FakeConfigFile.path)"))
    #expect(scenario.config == gaps)
    #expect(frames(scenario) == expectedFrames(gaps))
  }

  @Test func reloadKeepsTheRatio() async {
    let file = FakeConfigFile()
    let scenario = await scenario(file: file)
    await scenario.command("layout ratio +0.1")
    file.write(.config(gaps))

    await scenario.command("config reload")
    #expect(frames(scenario) == expectedFrames(gaps, mainRatio: 0.6))
  }

  @Test func reloadKeepsTheRowHeights() async {
    let file = FakeConfigFile()
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]], configFile: file)
    // Drag the divider between the stacked windows down, from 566 points to 700.
    scenario.pointer.isPrimaryButtonDown = true
    await scenario.moveByHand(2, to: CGRect(x: 928, y: 38, width: 872, height: 700))
    scenario.pointer.release(at: CGPoint(x: 1000, y: 100))
    await scenario.runUntilQuiet()
    file.write(.config(gaps))

    await scenario.command("config reload")
    let expected = TallLayout().frames(
      count: 3, in: area,
      state: TallLayoutState(rowWeights: [[], [700, 431]]),
      gaps: LayoutGaps(inner: 8, outer: 12))
    #expect([1, 2, 3].map { scenario.frame(of: $0) } == expected)
  }

  @Test func reloadGivesTheGapsToWorkspacesNotOnScreen() async {
    let file = FakeConfigFile()
    let scenario = await Scenario(workspaces: [1: [1], 2: [2]], configFile: file)
    file.write(.config(gaps))

    await scenario.command("config reload")
    await scenario.command("workspace focus next")
    #expect(scenario.frame(of: 2) == oneWindowFrame(gaps))
  }

  @Test func workspacesAddedByAReloadGetTheGaps() async {
    let file = FakeConfigFile()
    let scenario = await Scenario(workspaces: [1: [1, 2]], configFile: file)
    file.write(.config(Config(gaps: gaps.gaps, workspaces: Config.Workspaces(count: 6))))

    await scenario.command("config reload")
    await scenario.focus(2)
    await scenario.command("window move-to-workspace 6 --follow")
    #expect(scenario.workspaces[2] == 6)
    #expect(scenario.frame(of: 2) == oneWindowFrame(gaps))
  }

  @Test func aBrokenFileChangesNothing() async {
    let file = FakeConfigFile()
    let scenario = await scenario(config: gaps, file: file)
    scenario.windowSystem.clearRecordedCalls()
    file.write(.broken(.invalid("unknown setting 'gap'")))

    #expect(
      await scenario.command("config reload")
        == .error("\(FakeConfigFile.path): unknown setting 'gap' (the current settings stay)"))
    #expect(scenario.config == gaps)
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func aMissingFileMeansTheDefaults() async {
    let scenario = await scenario(config: gaps, file: FakeConfigFile(.missing))

    #expect(
      await scenario.command("config reload")
        == .message("no config file at \(FakeConfigFile.path), using the defaults"))
    #expect(scenario.config == Config())
    #expect(frames(scenario) == expectedFrames(Config()))
  }

  @Test func withTilingOffReloadMovesNothingUntilTilingIsBackOn() async {
    let file = FakeConfigFile()
    let scenario = await scenario(file: file)
    await scenario.command("tiling off")
    scenario.windowSystem.clearRecordedCalls()
    file.write(.config(gaps))

    #expect(await scenario.command("config reload") == .message("reloaded \(FakeConfigFile.path)"))
    #expect(scenario.windowSystem.moves.isEmpty)

    await scenario.command("tiling on")
    #expect(frames(scenario) == expectedFrames(gaps))
  }

  @Test func reloadWorksBeforePermissionIsGranted() async {
    let file = FakeConfigFile(.config(gaps))
    let scenario = await scenario(file: file, isTrusted: false)

    #expect(await scenario.command("config reload") == .message("reloaded \(FakeConfigFile.path)"))
    #expect(scenario.config == gaps)
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func theGapsSurviveAStopAndRestart() async {
    let scenario = await scenario(config: gaps)
    // tylerd stops the manager when the permission goes, and starts it when it comes back.
    scenario.harness.manager.stop()
    await scenario.grantPermission()
    #expect(frames(scenario) == expectedFrames(gaps))
  }

  @Test func reloadWithoutAConfigSourceIsAnError() async {
    let scenario = await scenario(file: nil)
    #expect(
      await scenario.command("config reload") == .error("tylerd was started without a config file"))
  }
}

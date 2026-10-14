import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// The config at startup and `reload`, driven through a fake backend and a fake config file.
@Suite("Config and reload")
@MainActor
struct ConfigReloadScenarios {
  private let area = FakeDisplays.main.visibleFrame
  private let gaps = Config(gaps: Config.Gaps(inner: 8, outer: 12))

  private func makeManager(
    config: Config = Config(),
    file: FakeConfigFile? = FakeConfigFile(),
    isTrusted: Bool = true
  ) -> (WindowManager, FakeBackend) {
    let harness = ManagerHarness(
      windows: spread([1, 2]), gate: FakeGate(isTrusted: isTrusted), config: config,
      configFile: file)
    return (harness.manager, harness.backend)
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

  private func frames(_ backend: FakeBackend) -> [CGRect] {
    [1, 2].compactMap { backend.frame(of: $0) }
  }

  @Test func theConfigGivenAtStartIsUsedForTheFirstTiling() {
    let (manager, backend) = makeManager(config: gaps)
    #expect(manager.config == gaps)
    #expect(frames(backend) == expectedFrames(gaps))
  }

  @Test func reloadAppliesNewGapsAndRetilesAtOnce() {
    let file = FakeConfigFile()
    let (manager, backend) = makeManager(file: file)
    file.write(.config(gaps))

    #expect(manager.reload() == .message("reloaded \(FakeConfigFile.path)"))
    #expect(manager.config == gaps)
    #expect(frames(backend) == expectedFrames(gaps))
  }

  @Test func reloadKeepsTheRatio() {
    let file = FakeConfigFile()
    let (manager, backend) = makeManager(file: file)
    _ = manager.adjustRatio(by: 0.1)
    file.write(.config(gaps))

    _ = manager.reload()
    #expect(frames(backend) == expectedFrames(gaps, mainRatio: 0.6))
  }

  @Test func reloadKeepsTheRowHeights() async {
    let file = FakeConfigFile()
    let pointer = FakePointer()
    let harness = ManagerHarness([1, 2, 3], configFile: file, pointer: pointer)
    await harness.settle()
    // Drag the divider between the stacked windows down, from 566 points to 700.
    pointer.isPrimaryButtonDown = true
    await harness.backend.userMoves(2, to: CGRect(x: 928, y: 38, width: 872, height: 700))
    pointer.release(at: CGPoint(x: 1000, y: 100))
    await harness.settle()
    file.write(.config(gaps))

    _ = harness.manager.reload()
    let expected = TallLayout().frames(
      count: 3, in: area,
      state: TallLayoutState(rowWeights: [[], [700, 431]]),
      gaps: LayoutGaps(inner: 8, outer: 12))
    #expect([1, 2, 3].map { harness.frame(of: $0) } == expected)
  }

  @Test func reloadGivesTheGapsToWorkspacesNotOnScreen() async {
    let file = FakeConfigFile()
    let harness = ManagerHarness([1, 2], configFile: file)
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.next, follow: false)
    file.write(.config(gaps))

    _ = harness.manager.reload()
    _ = harness.manager.switchWorkspace(.next)
    await harness.settle()
    #expect(harness.frame(of: 2) == oneWindowFrame(gaps))
  }

  @Test func workspacesAddedByAReloadGetTheGaps() async {
    let file = FakeConfigFile()
    let harness = ManagerHarness([1, 2], configFile: file)
    file.write(.config(Config(gaps: gaps.gaps, workspaces: Config.Workspaces(count: 6))))

    _ = harness.manager.reload()
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.number(6), follow: true)
    await harness.settle()
    #expect(harness.workspaces()[2] == 6)
    #expect(harness.frame(of: 2) == oneWindowFrame(gaps))
  }

  @Test func aBrokenFileChangesNothing() {
    let file = FakeConfigFile()
    let (manager, backend) = makeManager(config: gaps, file: file)
    file.write(.broken(.invalid("unknown setting 'gap'")))

    #expect(
      manager.reload()
        == .error("\(FakeConfigFile.path): unknown setting 'gap' (the current settings stay)"))
    #expect(manager.config == gaps)
    #expect(backend.moves.isEmpty)
  }

  @Test func aMissingFileMeansTheDefaults() {
    let (manager, backend) = makeManager(config: gaps, file: FakeConfigFile(.missing))

    #expect(
      manager.reload()
        == .message("no config file at \(FakeConfigFile.path), using the defaults"))
    #expect(manager.config == Config())
    #expect(frames(backend) == expectedFrames(Config()))
  }

  @Test func withTilingOffReloadMovesNothingUntilTilingIsBackOn() {
    let file = FakeConfigFile()
    let (manager, backend) = makeManager(file: file)
    _ = manager.setTiling(.off)
    file.write(.config(gaps))

    #expect(manager.reload() == .message("reloaded \(FakeConfigFile.path)"))
    #expect(backend.moves.isEmpty)

    _ = manager.setTiling(.on)
    #expect(frames(backend) == expectedFrames(gaps))
  }

  @Test func reloadWorksBeforePermissionIsGranted() {
    let file = FakeConfigFile(.config(gaps))
    let (manager, backend) = makeManager(file: file, isTrusted: false)

    #expect(manager.reload() == .message("reloaded \(FakeConfigFile.path)"))
    #expect(manager.config == gaps)
    #expect(backend.moves.isEmpty)
  }

  @Test func theGapsSurviveAStopAndRestart() {
    let (manager, backend) = makeManager(config: gaps)
    manager.stop()
    manager.startIfPermitted()
    #expect(frames(backend) == expectedFrames(gaps))
  }

  @Test func reloadWithoutAConfigSourceIsAnError() {
    let (manager, _) = makeManager(file: nil)
    #expect(manager.reload() == .error("tylerd was started without a config file"))
  }

  @Test func reloadIsRoutedToTheManager() {
    let (manager, _) = makeManager(file: FakeConfigFile(.config(gaps)))
    #expect(manager.handle(.reload) == .message("reloaded \(FakeConfigFile.path)"))
  }
}

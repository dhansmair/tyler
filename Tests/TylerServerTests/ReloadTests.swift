import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

/// The config at startup and `reload`, driven through a fake backend and a fake config file.
@Suite("Config and reload")
@MainActor
struct ReloadTests {
  private let area = FakeDisplays.main.visibleFrame
  private let gaps = Config(gaps: Config.Gaps(inner: 8, outer: 12))

  private func makeManager(
    config: Config = Config(),
    file: FakeConfigFile? = FakeConfigFile(),
    isTrusted: Bool = true
  ) -> (WindowManager, FakeBackend) {
    let backend = FakeBackend(windows: [
      makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
      makeWindow(id: 2, frame: CGRect(x: 150, y: 100, width: 300, height: 200)),
    ])
    let manager = WindowManager(
      backend: backend, displays: FakeDisplays(), gate: FakeGate(isTrusted: isTrusted),
      config: config, configSource: file?.source)
    manager.startIfPermitted()
    backend.clearRecordedCalls()
    return (manager, backend)
  }

  /// Where the tall layout puts windows 1 and 2 with these settings.
  private func expectedFrames(_ config: Config, mainRatio: Double = 0.5) -> [CGRect] {
    let parameters = LayoutParameters(
      mainRatio: mainRatio,
      outerGap: CGFloat(config.gaps.outer),
      innerGap: CGFloat(config.gaps.inner))
    return TallLayout().frames(count: 2, in: area, parameters: parameters)
  }

  private func frames(_ backend: FakeBackend) -> [CGRect] {
    [1, 2].compactMap { id in backend.windows.first { $0.id == WindowID(id) }?.frame }
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
    manager.adjustRatio(by: 0.1)
    file.write(.config(gaps))

    manager.reload()
    #expect(frames(backend) == expectedFrames(gaps, mainRatio: 0.6))
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
    manager.setTiling(.off)
    file.write(.config(gaps))

    #expect(manager.reload() == .message("reloaded \(FakeConfigFile.path)"))
    #expect(backend.moves.isEmpty)

    manager.setTiling(.on)
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

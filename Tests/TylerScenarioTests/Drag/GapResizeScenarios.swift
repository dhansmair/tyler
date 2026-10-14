import CoreGraphics
import Testing
import TylerConfig
import TylerCore

@testable import TylerServer

/// Dragging the gap between two tiled windows moves the divider between them. Three windows tile
/// `tall` with a gap of 10: window 1 on the left, window 2 above window 3 on the right.
@Suite("Resizing by dragging a gap")
@MainActor
struct GapResizeScenarios {
  private static func config(gap: Int = 10, gapResize: Bool = true) -> Config {
    var config = Config()
    config.gaps.inner = gap
    config.mouse.gapResize = gapResize
    return config
  }

  private static func scenario(config: Config = config()) async -> Scenario {
    await Scenario(workspaces: [1: [1, 2, 3]], config: config)
  }

  /// The middle of the gap beside window 1, level with window 2.
  private static func besideMain(_ scenario: Scenario) -> CGPoint {
    let main = scenario.frame(of: 1) ?? .null
    return CGPoint(x: main.maxX + 5, y: main.minY + 200)
  }

  @Test func draggingTheGapBesideTheMainWindowMovesTheDivider() async {
    let scenario = await Self.scenario()
    let before = scenario.frame(of: 1) ?? .null
    #expect(await scenario.dragGap(at: Self.besideMain(scenario), by: CGVector(dx: 120, dy: 40)))
    let main = scenario.frame(of: 1) ?? .null
    #expect(abs(main.maxX - (before.maxX + 120)) <= 1)
    #expect(main.minX == before.minX)
    #expect(scenario.frame(of: 2)?.minX == main.maxX + 10)
    #expect(scenario.frame(of: 3)?.minX == main.maxX + 10)
    #expect(scenario.list(1) == [1, 2, 3])
  }

  @Test func draggingTheGapBetweenStackedWindowsMovesTheirDivider() async {
    let scenario = await Self.scenario()
    let upper = scenario.frame(of: 2) ?? .null
    let main = scenario.frame(of: 1) ?? .null
    let gap = CGPoint(x: upper.midX, y: upper.maxY + 5)
    #expect(await scenario.dragGap(at: gap, by: CGVector(dx: 0, dy: -150)))
    let resized = scenario.frame(of: 2) ?? .null
    #expect(abs(resized.maxY - (upper.maxY - 150)) <= 1)
    #expect(scenario.frame(of: 3)?.minY == resized.maxY + 10)
    #expect(scenario.frame(of: 1) == main, "the main window stays")
  }

  @Test func leavesTheFocusAlone() async {
    let scenario = await Self.scenario()
    await scenario.focus(3)
    let focusCalls = scenario.harness.windowSystem.focusCalls.count
    await scenario.dragGap(at: Self.besideMain(scenario), by: CGVector(dx: 100, dy: 0))
    #expect(scenario.harness.windowSystem.focusCalls.count == focusCalls)
  }

  @Test func aWindowInFrontOfTheGapGetsThePress() async {
    let scenario = await Self.scenario()
    let point = Self.besideMain(scenario)
    let floating = StackedWindow(id: WindowID(99), layer: PointerFocus.normalLayer, owner: "Notes")
    scenario.stacking.overlays = [
      (floating, CGRect(x: point.x - 50, y: point.y - 50, width: 100, height: 100))
    ]
    #expect(!scenario.pointer.wouldCapture(.gap, at: point))
  }

  @Test func aPressInAWindowGoesToTheApp() async {
    let scenario = await Self.scenario()
    let inside = CGPoint(x: (scenario.frame(of: 1) ?? .null).midX, y: 300)
    #expect(!scenario.pointer.wouldCapture(.gap, at: inside))
  }

  @Test func withoutGapsThereIsNothingToDrag() async {
    let scenario = await Self.scenario(config: Self.config(gap: 0))
    let main = scenario.frame(of: 1) ?? .null
    #expect(!scenario.pointer.wouldCapture(.gap, at: CGPoint(x: main.maxX, y: 300)))
  }

  @Test func turnedOffTakesNoPressInAGap() async {
    let scenario = await Self.scenario(config: Self.config(gapResize: false))
    #expect(!scenario.pointer.takesGaps)
    #expect(!scenario.pointer.wouldCapture(.gap, at: Self.besideMain(scenario)))
  }

  @Test func nothingIsTakenWhileTilingIsOff() async {
    let scenario = await Self.scenario()
    let point = Self.besideMain(scenario)
    await scenario.command("tiling off")
    #expect(!scenario.pointer.wouldCapture(.gap, at: point))
  }
}

import CoreGraphics
import Testing
import TylerConfig
import TylerCore

@testable import TylerServer

/// The pointer over the gap between two tiled windows shows the resize cursor there. Three
/// windows tile `tall` with a gap of 10: window 1 on the left, window 2 above window 3 on the
/// right.
@Suite("The resize cursor over a gap")
@MainActor
struct GapCursorScenarios {
  private static func scenario(gap: Int = 10, gapResize: Bool = true) async -> Scenario {
    var config = Config()
    config.gaps.inner = gap
    config.mouse.gapResize = gapResize
    return await Scenario(workspaces: [1: [1, 2, 3]], config: config)
  }

  /// The gap beside window 1, along its whole height.
  private static func besideMain(_ scenario: Scenario) -> CGRect {
    let main = scenario.frame(of: 1) ?? .null
    return CGRect(x: main.maxX, y: main.minY, width: 10, height: main.height)
  }

  private static func middle(of area: CGRect) -> CGPoint {
    CGPoint(x: area.midX, y: area.minY + 200)
  }

  @Test func hoveringAGapShowsTheCursor() async {
    let scenario = await Self.scenario()
    let gap = Self.besideMain(scenario)
    await scenario.movePointer(to: Self.middle(of: gap))
    #expect(scenario.gapCursor.area == gap)
  }

  @Test func hoveringTheGapBetweenStackedWindowsShowsTheCursor() async {
    let scenario = await Self.scenario()
    let upper = scenario.frame(of: 2) ?? .null
    await scenario.movePointer(to: CGPoint(x: upper.midX, y: upper.maxY + 5))
    #expect(
      scenario.gapCursor.area
        == CGRect(x: upper.minX, y: upper.maxY, width: upper.width, height: 10))
  }

  @Test func movingIntoAWindowHidesIt() async {
    let scenario = await Self.scenario()
    await scenario.movePointer(to: Self.middle(of: Self.besideMain(scenario)))
    await scenario.movePointer(to: CGPoint(x: 300, y: 300))
    #expect(scenario.gapCursor.area == nil)
  }

  @Test func movingAlongAGapReadsTheWindowListOnce() async {
    let scenario = await Self.scenario()
    let gap = Self.besideMain(scenario)
    await scenario.movePointer(to: Self.middle(of: gap))
    await scenario.movePointer(to: CGPoint(x: gap.midX, y: gap.minY + 400))
    await scenario.movePointer(to: CGPoint(x: gap.midX, y: gap.minY + 600))
    #expect(scenario.stacking.queries.count == 1)
    #expect(scenario.gapCursor.showCount == 1)
  }

  @Test func aWindowInFrontOfTheGapKeepsItsCursor() async {
    let scenario = await Self.scenario()
    let point = Self.middle(of: Self.besideMain(scenario))
    let floating = StackedWindow(id: WindowID(99), layer: PointerFocus.normalLayer, owner: "Notes")
    scenario.stacking.overlays = [
      (floating, CGRect(x: point.x - 50, y: point.y - 50, width: 100, height: 100))
    ]
    await scenario.movePointer(to: point)
    #expect(scenario.gapCursor.area == nil)
  }

  @Test func draggingTheGapKeepsTheCursorOnIt() async {
    let scenario = await Self.scenario()
    let point = Self.middle(of: Self.besideMain(scenario))
    await scenario.movePointer(to: point)
    await scenario.dragGap(at: point, by: CGVector(dx: 120, dy: 0))
    #expect(scenario.gapCursor.hideCount == 0, "it follows the gap while dragging")
    #expect(scenario.gapCursor.area == Self.besideMain(scenario))
  }

  @Test func aLayoutChangeUnderTheStillPointerHidesIt() async {
    let scenario = await Self.scenario()
    await scenario.movePointer(to: Self.middle(of: Self.besideMain(scenario)))
    await scenario.command("layout set full")
    #expect(scenario.gapCursor.area == nil)
  }

  @Test func turnedOffShowsNothing() async {
    let scenario = await Self.scenario(gapResize: false)
    #expect(!scenario.pointer.watchesMoves, "focus follows mouse is off too")
    await scenario.movePointer(to: Self.middle(of: Self.besideMain(scenario)))
    #expect(scenario.gapCursor.showCount == 0)
  }

  @Test func withoutGapsShowsNothing() async {
    let scenario = await Self.scenario(gap: 0)
    let main = scenario.frame(of: 1) ?? .null
    await scenario.movePointer(to: CGPoint(x: main.maxX, y: 300))
    #expect(scenario.gapCursor.showCount == 0)
  }

  // A press in a gap is taken over only while the cursor shows there, since the interceptor's
  // active tap exists only then (`PressTakeover`).

  @Test func thePointerIsToldWhileTheCursorShows() async {
    let scenario = await Self.scenario()
    await scenario.movePointer(to: Self.middle(of: Self.besideMain(scenario)))
    #expect(scenario.pointer.isOverGap)
    await scenario.movePointer(to: CGPoint(x: 300, y: 300))
    #expect(!scenario.pointer.isOverGap)
  }

  @Test func aWindowInFrontOfTheGapTellsThePointerNothing() async {
    let scenario = await Self.scenario()
    let point = Self.middle(of: Self.besideMain(scenario))
    let floating = StackedWindow(id: WindowID(99), layer: PointerFocus.normalLayer, owner: "Notes")
    scenario.stacking.overlays = [
      (floating, CGRect(x: point.x - 50, y: point.y - 50, width: 100, height: 100))
    ]
    await scenario.movePointer(to: point)
    #expect(!scenario.pointer.isOverGap)
  }

  @Test func aLayoutChangeUnderTheStillPointerTellsThePointerItLeft() async {
    let scenario = await Self.scenario()
    await scenario.movePointer(to: Self.middle(of: Self.besideMain(scenario)))
    await scenario.command("layout set full")
    #expect(!scenario.pointer.isOverGap)
  }

  @Test func turnedOffTellsThePointerNothing() async {
    let scenario = await Self.scenario(gapResize: false)
    await scenario.movePointer(to: Self.middle(of: Self.besideMain(scenario)))
    #expect(!scenario.pointer.isOverGap)
  }
}

import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// macOS or the app decides where a new window appears, often on another display than the one in
/// use. It joins the workspace the user is on.
@Suite("Tiling: a new window opens on the focused display")
@MainActor
struct NewWindowDisplayScenarios {
  private static let onOtherDisplay = CGRect(
    x: FakeDisplays.secondary.frame.minX + 100, y: FakeDisplays.secondary.frame.minY + 100,
    width: 400, height: 300)

  private func twoDisplays(config: Config = Config()) async -> Scenario {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary],
      workspaces: [1: [1], 5: [2]], config: config)
    await scenario.focus(1)
    return scenario
  }

  @Test func aNewWindowOnAnotherDisplayJoinsTheFocusedOne() async {
    let scenario = await twoDisplays()
    await scenario.open(makeWindow(id: 9, frame: Self.onOtherDisplay))
    #expect(scenario.list(1) == [1, 9])
    #expect(scenario.list(5) == [2])
    #expect(scenario.frame(of: 9).map(FakeDisplays.main.frame.intersects) == true)
  }

  @Test func itsFocusDoesNotMoveTheFocusedDisplay() async {
    let scenario = await twoDisplays()
    await scenario.open(makeWindow(id: 9, frame: Self.onOtherDisplay))
    await scenario.focus(9)
    #expect(scenario.focusedDisplay == 1)
  }

  @Test func aFocusBeforeTheWindowCanBeTiledDoesNotMoveTheFocusedDisplay() async {
    let scenario = await twoDisplays()
    let window = makeWindow(id: 9, frame: Self.onOtherDisplay)
    var opening = window
    opening.isMinimized = true
    await scenario.open(opening)
    await scenario.focus(9)
    await scenario.change(window)
    #expect(scenario.focusedDisplay == 1)
    #expect(scenario.list(1) == [1, 9])
  }

  @Test func anEmptyWorkspaceTakesIt() async {
    let scenario = await twoDisplays()
    await scenario.command("workspace focus 3")
    await scenario.open(makeWindow(id: 9, frame: Self.onOtherDisplay))
    #expect(scenario.list(3) == [9])
  }

  @Test func anAppsAssignedWorkspaceWins() async {
    let config = Config(apps: ["app": Config.App(workspace: 6)])
    let scenario = await twoDisplays(config: config)
    await scenario.open(makeWindow(id: 9, frame: Self.onOtherDisplay))
    #expect(scenario.list(6) == [9])
    #expect(scenario.list(1) == [1])
  }

  /// A tab torn off a browser and dropped: the user put it there. Browsers open the window after
  /// the button comes up, so only the pointer tells.
  @Test func aWindowOpeningUnderThePointerStaysWhereItOpened() async {
    let scenario = await twoDisplays()
    scenario.pointer.move(to: CGPoint(x: Self.onOtherDisplay.midX, y: Self.onOtherDisplay.midY))
    await scenario.open(makeWindow(id: 9, frame: Self.onOtherDisplay))
    #expect(scenario.list(5) == [2, 9])
    #expect(scenario.list(1) == [1])
  }

  @Test func windowsOpenedWithTilingOffStayOnTheirDisplay() async {
    let scenario = await twoDisplays()
    await scenario.command("tiling off")
    await scenario.open(makeWindow(id: 9, frame: Self.onOtherDisplay))
    await scenario.command("tiling on")
    #expect(scenario.list(5) == [2, 9])
  }

  /// A window that never tiles keeps its first focus from moving the display, not every focus.
  @Test func aLaterFocusOnADialogMovesTheFocusedDisplay() async {
    let scenario = await twoDisplays()
    await scenario.open(makeWindow(id: 9, frame: Self.onOtherDisplay, kind: .dialog))
    await scenario.focus(9)
    #expect(scenario.focusedDisplay == 1)
    await scenario.focus(1)
    await scenario.focus(9)
    #expect(scenario.focusedDisplay == 2)
  }

  @Test func aFocusedWindowAssignedToTheOtherDisplayMovesTheFocusedDisplay() async {
    let scenario = await twoDisplays(config: Config(apps: ["app": Config.App(workspace: 5)]))
    var opening = makeWindow(id: 9, frame: Self.onOtherDisplay)
    opening.isMinimized = true
    await scenario.open(opening)
    await scenario.focus(9)
    await scenario.change(makeWindow(id: 9, frame: Self.onOtherDisplay))
    #expect(scenario.list(5) == [2, 9])
    #expect(scenario.focusedDisplay == 2)
  }

  @Test func aDialogStaysWhereItOpened() async {
    let scenario = await twoDisplays()
    await scenario.open(makeWindow(id: 9, frame: Self.onOtherDisplay, kind: .dialog))
    #expect(scenario.frame(of: 9) == Self.onOtherDisplay)
  }

  @Test func aWindowOpenAtStartStaysOnItsDisplay() async {
    let onMain = makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
    let scenario = await Scenario(
      openAtStart: [onMain, makeWindow(id: 2, frame: Self.onOtherDisplay)],
      displays: [FakeDisplays.main, FakeDisplays.secondary])
    #expect(scenario.list(1) == [1])
    #expect(scenario.list(5) == [2])
  }

  /// Only a window that hasn't been on a workspace is new.
  @Test func aWindowBackFromTheDockKeepsItsDisplay() async {
    let scenario = await twoDisplays()
    await scenario.open(makeWindow(id: 9))
    await scenario.change(makeWindow(id: 9, frame: Self.onOtherDisplay, isMinimized: true))
    await scenario.change(makeWindow(id: 9, frame: Self.onOtherDisplay))
    #expect(scenario.list(5) == [2, 9])
    #expect(scenario.list(1) == [1])
  }

  @Test func aWindowMovedToAnotherDisplayStaysThere() async {
    let scenario = await twoDisplays()
    var moved = makeWindow(id: 1, frame: Self.onOtherDisplay)
    moved.isFocused = false
    await scenario.change(moved)
    #expect(scenario.list(5).contains(1))
  }
}

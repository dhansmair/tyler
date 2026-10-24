import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@Suite("Tiling: reacting to windows")
@MainActor
struct WindowEventScenarios {
  private let area = FakeDisplays.main.visibleFrame

  // MARK: - Initial tiling

  @Test func existingWindowsAreTiledOnStart() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    #expect(scenario.windowSystem.moves.count == 2)
    #expect(scenario.list(1) == [1, 2])
    // Two windows: side by side across the visible area.
    #expect(scenario.frame(of: 1)?.minX == area.minX)
    #expect(scenario.frame(of: 2)?.maxX == area.maxX)
  }

  @Test func initialOrderFollowsPositionLeftToRight() async {
    // Created in id order 1, 2, 3 but sitting right to left on screen.
    let scenario = await Scenario(openAtStart: [
      makeWindow(id: 1, frame: CGRect(x: 900, y: 100, width: 300, height: 200)),
      makeWindow(id: 2, frame: CGRect(x: 500, y: 100, width: 300, height: 200)),
      makeWindow(id: 3, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
    ])
    #expect(scenario.list(1) == [3, 2, 1])
  }

  @Test func threeWindowsGiveOneLeftAndTwoStackedRight() async {
    let scenario = await Scenario(openAtStart: spread([1, 2, 3]))
    let main = scenario.frame(of: 1)
    let top = scenario.frame(of: 2)
    let bottom = scenario.frame(of: 3)
    #expect(main?.height == area.height)
    #expect(top?.minX == bottom?.minX)
    #expect(top?.maxY == bottom?.minY)
    #expect((top?.height ?? 0) + (bottom?.height ?? 0) == area.height)
  }

  @Test func windowsThatAreNeverTiledAreLeftAlone() async {
    let scenario = await Scenario(openAtStart: [
      makeWindow(id: 1),
      makeWindow(id: 2, kind: .dialog),
      makeWindow(id: 3, kind: .floating),
      makeWindow(id: 4, isMinimized: true),
      makeWindow(id: 5, isFullscreen: true),
    ])
    #expect(scenario.list(1) == [1])
    #expect(scenario.windowSystem.moves.map(\.id.rawValue) == [1])
  }

  @Test func windowsOnAnotherDisplayAreTiledOnItsCurrentWorkspace() async {
    let scenario = await Scenario(
      openAtStart: [
        makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
        makeWindow(id: 2, frame: CGRect(x: 0, y: -1000, width: 300, height: 200)),
      ], displays: [FakeDisplays.main, FakeDisplays.secondary])
    #expect(scenario.workspaces == [1: 1, 2: 5])
    #expect(scenario.frame(of: 1) == scenario.rect(.full))
    #expect(scenario.frame(of: 2) == scenario.rect(.full, display: 2))
  }

  @Test func withNoDisplaysNothingIsTiled() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]), displays: [])
    #expect(scenario.workspaces.isEmpty)
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  // MARK: - Reacting to events

  @Test func aNewWindowIsInsertedAfterTheFocusedOneAndRetiles() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    await scenario.open(makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200)))
    #expect(scenario.list(1) == [1, 9, 2])
    #expect(!scenario.windowSystem.moves.isEmpty)
  }

  @Test func closingAWindowRetilesTheRest() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    scenario.windowSystem.clearRecordedCalls()
    await scenario.close(2)
    #expect(scenario.list(1) == [1, 3])
    #expect(scenario.windowSystem.moves.map(\.id.rawValue).contains(3))
  }

  @Test func minimizingLeavesTheListAndRestoringBringsItBack() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.change(makeWindow(id: 2, isMinimized: true))
    #expect(scenario.list(1) == [1])
    // Master alone now fills the area.
    #expect(scenario.frame(of: 1) == area)

    await scenario.change(makeWindow(id: 2, frame: CGRect(x: 300, y: 100, width: 300, height: 200)))
    #expect(scenario.list(1) == [1, 2])
  }

  @Test func enteringAndLeavingFullscreenTakesAWindowOutOfAndBackIntoTheList() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.change(makeWindow(id: 1, isFullscreen: true))
    #expect(scenario.list(1) == [2])

    await scenario.change(makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200)))
    #expect(scenario.list(1).contains(1))
  }

  @Test func movingOrResizingAWindowCausesNoRetile() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    scenario.windowSystem.clearRecordedCalls()
    // The user drags window 1 somewhere else, then resizes window 2.
    await scenario.moveByHand(1, to: CGRect(x: 600, y: 400, width: 300, height: 200))
    await scenario.moveByHand(2, to: CGRect(x: 0, y: 0, width: 999, height: 111))
    #expect(scenario.windowSystem.moves.isEmpty, "a drag must not trigger any setFrame")
    #expect(scenario.list(1) == [1, 2])
  }

  @Test func aWindowMovedToAnotherDisplayJoinsItsWorkspaceAndTheRestRetile() async {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: [1, 2]])
    await scenario.moveByHand(2, to: CGRect(x: 0, y: -1000, width: 300, height: 200))
    #expect(scenario.workspaces == [1: 1, 2: 5])
    #expect(scenario.frame(of: 1) == scenario.rect(.full), "window 1 fills the display alone")
    #expect(scenario.frame(of: 2) == scenario.rect(.full, display: 2))
  }

  @Test func aWindowMovedInFromAnotherDisplayGoesLast() async {
    let elsewhere = makeWindow(id: 3, frame: CGRect(x: 0, y: -1000, width: 300, height: 200))
    let scenario = await Scenario(
      openAtStart: spread([1, 2]) + [elsewhere],
      displays: [FakeDisplays.main, FakeDisplays.secondary])
    #expect(scenario.workspaces == [1: 1, 2: 1, 3: 5])
    await scenario.moveByHand(3, to: CGRect(x: 600, y: 100, width: 300, height: 200))
    #expect(scenario.workspaces == [1: 1, 2: 1, 3: 1])
    #expect(scenario.list(1) == [1, 2, 3])
  }

  @Test func anUpdateForAWindowNotSeenYetTilesIt() async {
    // The Accessibility API can report a window's first move before its creation.
    let scenario = await Scenario(workspaces: [1: [1]])
    await scenario.change(makeWindow(id: 9, frame: CGRect(x: 600, y: 100, width: 300, height: 200)))
    #expect(scenario.list(1) == [1, 9])
  }

  @Test func aWindowTurningIntoADialogLeavesTheList() async throws {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    var dialog = try #require(scenario.windowSystem.windows.first { $0.id.rawValue == 2 })
    dialog.kind = .dialog
    await scenario.change(dialog)
    #expect(scenario.list(1) == [1])
  }

  @Test func aTitleChangeCausesNoRetile() async throws {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    var renamed = try #require(scenario.windowSystem.windows.first { $0.id.rawValue == 1 })
    renamed.title = "new title"
    scenario.windowSystem.clearRecordedCalls()
    await scenario.change(renamed)
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func theOperatingSystemFocusingATiledWindowUpdatesTheFocus() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(3)
    await scenario.command("window swap master")
    // Window 3 had focus, so it is the one that moved to the master slot.
    #expect(scenario.list(1).first == 3)
  }

  @Test func focusingAnUntiledWindowDoesNotChangeTheFocusedTile() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]) + [makeWindow(id: 7, kind: .dialog)])
    await scenario.focus(2)
    await scenario.focus(7)
    await scenario.command("window swap master")
    #expect(scenario.list(1).first == 2, "swap is relative to the last tiled window you used")
  }

  // MARK: - Applying layouts

  @Test func windowsAlreadyInPlaceAreNotMovedAgain() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    scenario.windowSystem.clearRecordedCalls()
    // Everything is already in its slot, so a layout change that yields the same frames is free.
    await scenario.command("layout set tall")
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func retileMovesEveryWindowEvenIfItLooksInPlace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    scenario.windowSystem.clearRecordedCalls()
    #expect(await scenario.command("workspace retile") == .ok)
    #expect(scenario.windowSystem.moves.map(\.id.rawValue).sorted() == [1, 2])
  }

  @Test func retilePutsAWindowYouDraggedBackIntoItsSlot() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    scenario.windowSystem.clearRecordedCalls()
    await scenario.moveByHand(1, to: CGRect(x: 900, y: 700, width: 200, height: 100))
    #expect(scenario.windowSystem.moves.isEmpty)
    await scenario.command("workspace retile")
    #expect(scenario.frame(of: 1)?.minX == area.minX)
  }

  @Test func oneWindowFailingDoesNotStopTheOthersAndIsReported() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    scenario.windowSystem.clearRecordedCalls()
    scenario.windowSystem.failingMoves = [WindowID(2)]
    #expect(await scenario.command("workspace retile") == .message("1 window could not be placed"))
    #expect(Set(scenario.windowSystem.moves.map(\.id.rawValue)) == [1, 3])
  }

  @Test func severalFailuresArePluralised() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    scenario.windowSystem.failingMoves = [WindowID(1), WindowID(2)]
    #expect(
      await scenario.command("workspace retile") == .message("2 windows could not be placed"))
  }
}

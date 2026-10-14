import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Tiling: reacting to windows, driven through a fake window system.
@Suite("Tiling: reacting to windows")
@MainActor
struct WindowEventScenarios {
  private let area = FakeDisplays.main.visibleFrame

  // MARK: - Initial tiling

  @Test func existingWindowsAreTiledOnStart() {
    let harness = ManagerHarness(windows: spread([1, 2]), clearRecordedCalls: false)
    #expect(harness.windowSystem.moves.count == 2)
    #expect(harness.manager.slots == [1: 1, 2: 2])
    // Two windows: side by side across the visible area.
    #expect(harness.frame(of: 1)?.minX == area.minX)
    #expect(harness.frame(of: 2)?.maxX == area.maxX)
  }

  @Test func initialOrderFollowsPositionLeftToRight() {
    // Created in id order 1, 2, 3 but sitting right to left on screen.
    let windows = [
      makeWindow(id: 1, frame: CGRect(x: 900, y: 100, width: 300, height: 200)),
      makeWindow(id: 2, frame: CGRect(x: 500, y: 100, width: 300, height: 200)),
      makeWindow(id: 3, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
    ]
    let harness = ManagerHarness(windows: windows)
    #expect(harness.manager.slots == [3: 1, 2: 2, 1: 3])
  }

  @Test func threeWindowsGiveOneLeftAndTwoStackedRight() {
    let harness = ManagerHarness(windows: spread([1, 2, 3]), clearRecordedCalls: false)
    let main = harness.frame(of: 1)
    let top = harness.frame(of: 2)
    let bottom = harness.frame(of: 3)
    #expect(main?.height == area.height)
    #expect(top?.minX == bottom?.minX)
    #expect(top?.maxY == bottom?.minY)
    #expect((top?.height ?? 0) + (bottom?.height ?? 0) == area.height)
  }

  @Test func windowsThatAreNeverTiledAreLeftAlone() {
    let windows = [
      makeWindow(id: 1),
      makeWindow(id: 2, kind: .dialog),
      makeWindow(id: 3, kind: .floating),
      makeWindow(id: 4, isMinimized: true),
      makeWindow(id: 5, isFullscreen: true),
    ]
    let harness = ManagerHarness(windows: windows, clearRecordedCalls: false)
    #expect(harness.manager.slots == [1: 1])
    #expect(harness.windowSystem.moves.map(\.id.rawValue) == [1])
  }

  @Test func windowsOnAnotherDisplayAreTiledOnItsCurrentWorkspace() {
    let windows = [
      makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
      makeWindow(id: 2, frame: CGRect(x: 0, y: -1000, width: 300, height: 200)),
    ]
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
    let harness = ManagerHarness(windows: windows, displays: displays)
    #expect(harness.workspaces() == [1: 1, 2: 5])
    #expect(harness.frame(of: 1) == harness.area)
    #expect(harness.frame(of: 2) == FakeDisplays.secondary.visibleFrame)
  }

  @Test func withNoDisplaysNothingIsTiled() {
    let harness = ManagerHarness(
      windows: spread([1, 2]), displays: FakeDisplays(displays: []), clearRecordedCalls: false)
    #expect(harness.manager.slots.isEmpty)
    #expect(harness.windowSystem.moves.isEmpty)
  }

  // MARK: - Reacting to events

  @Test func aNewWindowIsInsertedAfterTheFocusedOneAndRetiles() async {
    let harness = ManagerHarness([1, 2])
    harness.windowSystem.send(.focused(WindowID(1)))
    harness.windowSystem.send(
      .created(makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))))
    await settle()
    #expect(harness.manager.slots == [1: 1, 9: 2, 2: 3])
    #expect(!harness.windowSystem.moves.isEmpty)
  }

  @Test func closingAWindowRetilesTheRest() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.windowSystem.send(.destroyed(WindowID(2)))
    await settle()
    #expect(harness.manager.slots == [1: 1, 3: 2])
    #expect(harness.windowSystem.moves.map(\.id.rawValue).contains(3))
  }

  @Test func minimizingLeavesTheListAndRestoringBringsItBack() async {
    let harness = ManagerHarness([1, 2])
    harness.windowSystem.send(.updated(makeWindow(id: 2, isMinimized: true)))
    await settle()
    #expect(harness.manager.slots == [1: 1])
    // Master alone now fills the area.
    #expect(harness.frame(of: 1) == area)

    harness.windowSystem.send(
      .updated(makeWindow(id: 2, frame: CGRect(x: 300, y: 100, width: 300, height: 200))))
    await settle()
    #expect(harness.manager.slots == [1: 1, 2: 2])
  }

  @Test func enteringAndLeavingFullscreenTakesAWindowOutOfAndBackIntoTheList() async {
    let harness = ManagerHarness([1, 2])
    harness.windowSystem.send(.updated(makeWindow(id: 1, isFullscreen: true)))
    await settle()
    #expect(harness.manager.slots == [2: 1])

    harness.windowSystem.send(
      .updated(makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200))))
    await settle()
    #expect(harness.manager.slots[1] != nil)
  }

  @Test func movingOrResizingAWindowCausesNoRetile() async {
    let harness = ManagerHarness([1, 2])
    // The user drags window 1 somewhere else, then resizes window 2.
    harness.windowSystem.send(
      .updated(makeWindow(id: 1, frame: CGRect(x: 600, y: 400, width: 300, height: 200))))
    harness.windowSystem.send(
      .updated(makeWindow(id: 2, frame: CGRect(x: 0, y: 0, width: 999, height: 111))))
    await settle()
    #expect(harness.windowSystem.moves.isEmpty, "a drag must not trigger any setFrame")
    #expect(harness.manager.slots == [1: 1, 2: 2])
  }

  @Test func aWindowMovedToAnotherDisplayJoinsItsWorkspaceAndTheRestRetile() async {
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
    let harness = ManagerHarness(windows: spread([1, 2]), displays: displays)
    await harness.windowSystem.userMoves(2, to: CGRect(x: 0, y: -1000, width: 300, height: 200))
    #expect(harness.workspaces() == [1: 1, 2: 5])
    #expect(harness.frame(of: 1) == harness.area, "window 1 fills the display alone")
    #expect(harness.frame(of: 2) == FakeDisplays.secondary.visibleFrame)
  }

  @Test func aWindowMovedInFromAnotherDisplayGoesLast() async {
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
    let elsewhere = makeWindow(id: 3, frame: CGRect(x: 0, y: -1000, width: 300, height: 200))
    let harness = ManagerHarness(windows: spread([1, 2]) + [elsewhere], displays: displays)
    #expect(harness.workspaces() == [1: 1, 2: 1, 3: 5])
    await harness.windowSystem.userMoves(3, to: CGRect(x: 600, y: 100, width: 300, height: 200))
    #expect(harness.workspaces() == [1: 1, 2: 1, 3: 1])
    #expect(harness.manager.slots == [1: 1, 2: 2, 3: 3])
  }

  @Test func anUpdateForAWindowNotSeenYetTilesIt() async {
    // The Accessibility API can report a window's first move before its creation.
    let harness = ManagerHarness([1])
    harness.windowSystem.send(
      .updated(makeWindow(id: 9, frame: CGRect(x: 600, y: 100, width: 300, height: 200))))
    await settle()
    #expect(harness.manager.slots == [1: 1, 9: 2])
  }

  @Test func aWindowTurningIntoADialogLeavesTheList() async {
    let harness = ManagerHarness([1, 2])
    var dialog = harness.windowSystem.windows[1]
    dialog.kind = .dialog
    harness.windowSystem.send(.updated(dialog))
    await settle()
    #expect(harness.manager.slots == [1: 1])
  }

  @Test func aTitleChangeCausesNoRetile() async {
    let harness = ManagerHarness([1, 2])
    let current = harness.windowSystem.windows[0]
    var renamed = current
    renamed.title = "new title"
    harness.windowSystem.send(.updated(renamed))
    await settle()
    #expect(harness.windowSystem.moves.isEmpty)
  }

  @Test func theOperatingSystemFocusingATiledWindowUpdatesTheFocus() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.windowSystem.send(.focused(WindowID(3)))
    await settle()
    _ = harness.manager.swap(.main)
    // Window 3 had focus, so it is the one that moved to the master slot.
    #expect(harness.manager.slots[3] == 1)
  }

  @Test func focusingAnUntiledWindowDoesNotChangeTheFocusedTile() async {
    let windows = spread([1, 2]) + [makeWindow(id: 7, kind: .dialog)]
    let harness = ManagerHarness(windows: windows)
    harness.windowSystem.send(.focused(WindowID(2)))
    harness.windowSystem.send(.focused(WindowID(7)))
    await settle()
    _ = harness.manager.swap(.main)
    #expect(harness.manager.slots[2] == 1, "swap is relative to the last tiled window you used")
  }

  // MARK: - Applying layouts

  @Test func windowsAlreadyInPlaceAreNotMovedAgain() async {
    let harness = ManagerHarness([1, 2])
    // The manager learns the new frames from the window system's `updated` events, which arrive
    // asynchronously; wait for them, otherwise it still sees the old frames.
    await settle()
    // Everything is already in its slot, so a layout change that yields the same frames is free.
    _ = harness.manager.setLayout(.set(.tall))
    #expect(harness.windowSystem.moves.isEmpty)
  }

  @Test func retileMovesEveryWindowEvenIfItLooksInPlace() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.retile() == .ok)
    #expect(harness.windowSystem.moves.map(\.id.rawValue).sorted() == [1, 2])
  }

  @Test func retilePutsAWindowYouDraggedBackIntoItsSlot() async {
    let harness = ManagerHarness([1, 2])
    harness.windowSystem.send(
      .updated(makeWindow(id: 1, frame: CGRect(x: 900, y: 700, width: 200, height: 100))))
    await settle()
    #expect(harness.windowSystem.moves.isEmpty)
    _ = harness.manager.retile()
    #expect(harness.frame(of: 1)?.minX == area.minX)
  }

  @Test func oneWindowFailingDoesNotStopTheOthersAndIsReported() {
    let harness = ManagerHarness([1, 2, 3])
    harness.windowSystem.failingMoves = [WindowID(2)]
    let response = harness.manager.retile()
    #expect(response == .message("1 window could not be placed"))
    #expect(Set(harness.windowSystem.moves.map(\.id.rawValue)) == [1, 3])
  }

  @Test func severalFailuresArePluralised() {
    let harness = ManagerHarness([1, 2, 3])
    harness.windowSystem.failingMoves = [WindowID(1), WindowID(2)]
    #expect(harness.manager.retile() == .message("2 windows could not be placed"))
  }
}

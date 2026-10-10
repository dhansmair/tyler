import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

/// Tiling: reacting to windows, driven through a fake backend.
@Suite("Tiling: reacting to windows")
@MainActor
struct TilingTests {
  private let area = FakeDisplays.main.visibleFrame

  // MARK: - Initial tiling

  @Test func existingWindowsAreTiledOnStart() {
    let harness = ManagerHarness(windows: spread([1, 2]), clearRecordedCalls: false)
    #expect(harness.backend.moves.count == 2)
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
    #expect(harness.backend.moves.map(\.id.rawValue) == [1])
  }

  @Test func windowsOnAnotherDisplayAreNotTiled() {
    let windows = [
      makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
      makeWindow(id: 2, frame: CGRect(x: 2000, y: 100, width: 300, height: 200)),
    ]
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
    let harness = ManagerHarness(windows: windows, displays: displays)
    #expect(harness.manager.slots == [1: 1])
  }

  @Test func withNoDisplaysNothingIsTiled() {
    let harness = ManagerHarness(
      windows: spread([1, 2]), displays: FakeDisplays(displays: []), clearRecordedCalls: false)
    #expect(harness.manager.slots.isEmpty)
    #expect(harness.backend.moves.isEmpty)
  }

  // MARK: - Reacting to events

  @Test func aNewWindowIsInsertedAfterTheFocusedOneAndRetiles() async {
    let harness = ManagerHarness([1, 2])
    harness.backend.send(.focused(WindowID(1)))
    harness.backend.send(
      .created(makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))))
    await settle()
    #expect(harness.manager.slots == [1: 1, 9: 2, 2: 3])
    #expect(!harness.backend.moves.isEmpty)
  }

  @Test func closingAWindowRetilesTheRest() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.backend.send(.destroyed(WindowID(2)))
    await settle()
    #expect(harness.manager.slots == [1: 1, 3: 2])
    #expect(harness.backend.moves.map(\.id.rawValue).contains(3))
  }

  @Test func minimizingLeavesTheListAndRestoringBringsItBack() async {
    let harness = ManagerHarness([1, 2])
    harness.backend.send(.updated(makeWindow(id: 2, isMinimized: true)))
    await settle()
    #expect(harness.manager.slots == [1: 1])
    // Master alone now fills the area.
    #expect(harness.frame(of: 1) == area)

    harness.backend.send(
      .updated(makeWindow(id: 2, frame: CGRect(x: 300, y: 100, width: 300, height: 200))))
    await settle()
    #expect(harness.manager.slots == [1: 1, 2: 2])
  }

  @Test func enteringAndLeavingFullscreenTakesAWindowOutOfAndBackIntoTheList() async {
    let harness = ManagerHarness([1, 2])
    harness.backend.send(.updated(makeWindow(id: 1, isFullscreen: true)))
    await settle()
    #expect(harness.manager.slots == [2: 1])

    harness.backend.send(
      .updated(makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200))))
    await settle()
    #expect(harness.manager.slots[1] != nil)
  }

  @Test func movingOrResizingAWindowCausesNoRetile() async {
    let harness = ManagerHarness([1, 2])
    // The user drags window 1 somewhere else, then resizes window 2.
    harness.backend.send(
      .updated(makeWindow(id: 1, frame: CGRect(x: 600, y: 400, width: 300, height: 200))))
    harness.backend.send(
      .updated(makeWindow(id: 2, frame: CGRect(x: 0, y: 0, width: 999, height: 111))))
    await settle()
    #expect(harness.backend.moves.isEmpty, "a drag must not trigger any setFrame")
    #expect(harness.manager.slots == [1: 1, 2: 2])
  }

  @Test func aWindowDraggedToAnotherDisplayLeavesTheListAndTheRestRetile() async {
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
    let harness = ManagerHarness(windows: spread([1, 2]), displays: displays)
    harness.backend.send(
      .updated(makeWindow(id: 2, frame: CGRect(x: 2000, y: 100, width: 300, height: 200))))
    await settle()
    #expect(harness.manager.slots == [1: 1])
    #expect(harness.frame(of: 1) == harness.area, "window 1 fills the display alone")
  }

  @Test func aWindowDraggedInFromAnotherDisplayJoinsTheList() async {
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
    let elsewhere = makeWindow(id: 3, frame: CGRect(x: 2000, y: 100, width: 300, height: 200))
    let harness = ManagerHarness(windows: spread([1, 2]) + [elsewhere], displays: displays)
    #expect(harness.manager.slots == [1: 1, 2: 2])
    harness.backend.send(
      .updated(makeWindow(id: 3, frame: CGRect(x: 600, y: 100, width: 300, height: 200))))
    await settle()
    #expect(harness.manager.slots[3] != nil)
  }

  @Test func anUpdateForAWindowNotSeenYetTilesIt() async {
    // The Accessibility API can report a window's first move before its creation.
    let harness = ManagerHarness([1])
    harness.backend.send(
      .updated(makeWindow(id: 9, frame: CGRect(x: 600, y: 100, width: 300, height: 200))))
    await settle()
    #expect(harness.manager.slots == [1: 1, 9: 2])
  }

  @Test func aWindowTurningIntoADialogLeavesTheList() async {
    let harness = ManagerHarness([1, 2])
    var dialog = harness.backend.windows[1]
    dialog.kind = .dialog
    harness.backend.send(.updated(dialog))
    await settle()
    #expect(harness.manager.slots == [1: 1])
  }

  @Test func aTitleChangeCausesNoRetile() async {
    let harness = ManagerHarness([1, 2])
    let current = harness.backend.windows[0]
    var renamed = current
    renamed.title = "new title"
    harness.backend.send(.updated(renamed))
    await settle()
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func theOperatingSystemFocusingATiledWindowUpdatesTheFocus() async {
    let harness = ManagerHarness([1, 2, 3])
    harness.backend.send(.focused(WindowID(3)))
    await settle()
    _ = harness.manager.swap(.main)
    // Window 3 had focus, so it is the one that moved to the master slot.
    #expect(harness.manager.slots[3] == 1)
  }

  @Test func focusingAnUntiledWindowDoesNotChangeTheFocusedTile() async {
    let windows = spread([1, 2]) + [makeWindow(id: 7, kind: .dialog)]
    let harness = ManagerHarness(windows: windows)
    harness.backend.send(.focused(WindowID(2)))
    harness.backend.send(.focused(WindowID(7)))
    await settle()
    _ = harness.manager.swap(.main)
    #expect(harness.manager.slots[2] == 1, "swap is relative to the last tiled window you used")
  }

  // MARK: - Applying layouts

  @Test func windowsAlreadyInPlaceAreNotMovedAgain() async {
    let harness = ManagerHarness([1, 2])
    // The harness.manager learns the new frames from the harness.backend's `updated` events, which arrive
    // asynchronously; wait for them, otherwise it still sees the old frames.
    await settle()
    // Everything is already in its slot, so a layout change that yields the same frames is free.
    _ = harness.manager.setLayout(.set(.tall))
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func retileMovesEveryWindowEvenIfItLooksInPlace() {
    let harness = ManagerHarness([1, 2])
    #expect(harness.manager.retile() == .ok)
    #expect(harness.backend.moves.map(\.id.rawValue).sorted() == [1, 2])
  }

  @Test func retilePutsAWindowYouDraggedBackIntoItsSlot() async {
    let harness = ManagerHarness([1, 2])
    harness.backend.send(
      .updated(makeWindow(id: 1, frame: CGRect(x: 900, y: 700, width: 200, height: 100))))
    await settle()
    #expect(harness.backend.moves.isEmpty)
    _ = harness.manager.retile()
    #expect(harness.frame(of: 1)?.minX == area.minX)
  }

  @Test func oneWindowFailingDoesNotStopTheOthersAndIsReported() {
    let harness = ManagerHarness([1, 2, 3])
    harness.backend.failingMoves = [WindowID(2)]
    let response = harness.manager.retile()
    #expect(response == .message("1 window could not be placed"))
    #expect(Set(harness.backend.moves.map(\.id.rawValue)) == [1, 3])
  }

  @Test func severalFailuresArePluralised() {
    let harness = ManagerHarness([1, 2, 3])
    harness.backend.failingMoves = [WindowID(1), WindowID(2)]
    #expect(harness.manager.retile() == .message("2 windows could not be placed"))
  }
}

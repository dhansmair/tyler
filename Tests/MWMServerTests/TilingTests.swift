import CoreGraphics
import MWMCore
import Testing

@testable import MWMServer

/// Tiling: reacting to windows, driven through a fake backend.
@Suite("Tiling: reacting to windows")
@MainActor
struct TilingTests {
  private let area = FakeDisplays.main.visibleFrame

  /// A manager with `count` standard windows spread left to right on the primary display,
  /// already started (so the initial tiling has happened) and with recorded calls cleared.
  private func makeStarted(
    windows: [WindowInfo],
    displays: FakeDisplays = FakeDisplays(),
    clearRecordedCalls: Bool = true
  ) -> (WindowManager, FakeBackend) {
    let backend = FakeBackend(windows: windows)
    let manager = WindowManager(
      backend: backend, displays: displays, gate: FakeGate(isTrusted: true))
    manager.startIfPermitted()
    if clearRecordedCalls { backend.clearRecordedCalls() }
    return (manager, backend)
  }

  private func spread(_ ids: UInt32...) -> [WindowInfo] {
    ids.enumerated().map { index, windowID in
      makeWindow(
        id: windowID,
        frame: CGRect(x: 100 + index * 50, y: 100, width: 300, height: 200))
    }
  }

  /// Lets the manager's event-pump task run.
  private func settle() async {
    for _ in 0..<30 { await Task.yield() }
  }

  private func listed(_ manager: WindowManager) -> [WindowInfo] {
    guard case .windows(let windows) = manager.windows() else { return [] }
    return windows
  }

  private func slots(_ manager: WindowManager) -> [UInt32: Int] {
    Dictionary(
      uniqueKeysWithValues: listed(manager).compactMap { window in
        window.slot.map { (window.id.rawValue, $0) }
      })
  }

  private func frame(of windowID: UInt32, in backend: FakeBackend) -> CGRect? {
    backend.windows.first { $0.id.rawValue == windowID }?.frame
  }

  // MARK: - Initial tiling

  @Test func existingWindowsAreTiledOnStart() {
    let (manager, backend) = makeStarted(
      windows: spread(1, 2), clearRecordedCalls: false)
    #expect(backend.moves.count == 2)
    #expect(slots(manager) == [1: 1, 2: 2])
    // Two windows: side by side across the visible area.
    #expect(frame(of: 1, in: backend)?.minX == area.minX)
    #expect(frame(of: 2, in: backend)?.maxX == area.maxX)
  }

  @Test func initialOrderFollowsPositionLeftToRight() {
    // Created in id order 1, 2, 3 but sitting right to left on screen.
    let windows = [
      makeWindow(id: 1, frame: CGRect(x: 900, y: 100, width: 300, height: 200)),
      makeWindow(id: 2, frame: CGRect(x: 500, y: 100, width: 300, height: 200)),
      makeWindow(id: 3, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
    ]
    let (manager, _) = makeStarted(windows: windows)
    #expect(slots(manager) == [3: 1, 2: 2, 1: 3])
  }

  @Test func threeWindowsGiveOneLeftAndTwoStackedRight() {
    let (_, backend) = makeStarted(windows: spread(1, 2, 3), clearRecordedCalls: false)
    let main = frame(of: 1, in: backend)
    let top = frame(of: 2, in: backend)
    let bottom = frame(of: 3, in: backend)
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
    let (manager, backend) = makeStarted(windows: windows, clearRecordedCalls: false)
    #expect(slots(manager) == [1: 1])
    #expect(backend.moves.map(\.id.rawValue) == [1])
  }

  @Test func windowsOnAnotherDisplayAreNotTiled() {
    let windows = [
      makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200)),
      makeWindow(id: 2, frame: CGRect(x: 2000, y: 100, width: 300, height: 200)),
    ]
    let displays = FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
    let (manager, _) = makeStarted(windows: windows, displays: displays)
    #expect(slots(manager) == [1: 1])
  }

  @Test func withNoDisplaysNothingIsTiled() {
    let (manager, backend) = makeStarted(
      windows: spread(1, 2), displays: FakeDisplays(displays: []), clearRecordedCalls: false)
    #expect(slots(manager).isEmpty)
    #expect(backend.moves.isEmpty)
  }

  // MARK: - Reacting to events

  @Test func aNewWindowIsInsertedAfterTheFocusedOneAndRetiles() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    backend.send(.focused(WindowID(1)))
    backend.send(
      .created(makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))))
    await settle()
    #expect(slots(manager) == [1: 1, 9: 2, 2: 3])
    #expect(!backend.moves.isEmpty)
  }

  @Test func closingAWindowRetilesTheRest() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    backend.send(.destroyed(WindowID(2)))
    await settle()
    #expect(slots(manager) == [1: 1, 3: 2])
    #expect(backend.moves.map(\.id.rawValue).contains(3))
  }

  @Test func minimizingLeavesTheListAndRestoringBringsItBack() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    backend.send(.updated(makeWindow(id: 2, isMinimized: true)))
    await settle()
    #expect(slots(manager) == [1: 1])
    // Master alone now fills the area.
    #expect(frame(of: 1, in: backend) == area)

    backend.send(
      .updated(makeWindow(id: 2, frame: CGRect(x: 300, y: 100, width: 300, height: 200))))
    await settle()
    #expect(slots(manager) == [1: 1, 2: 2])
  }

  @Test func enteringAndLeavingFullscreenTakesAWindowOutOfAndBackIntoTheList() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    backend.send(.updated(makeWindow(id: 1, isFullscreen: true)))
    await settle()
    #expect(slots(manager) == [2: 1])

    backend.send(
      .updated(makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200))))
    await settle()
    #expect(slots(manager)[1] != nil)
  }

  @Test func movingOrResizingAWindowCausesNoRetile() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    // The user drags window 1 somewhere else, then resizes window 2.
    backend.send(
      .updated(makeWindow(id: 1, frame: CGRect(x: 600, y: 400, width: 300, height: 200))))
    backend.send(.updated(makeWindow(id: 2, frame: CGRect(x: 0, y: 0, width: 999, height: 111))))
    await settle()
    #expect(backend.moves.isEmpty, "a drag must not trigger any setFrame")
    #expect(slots(manager) == [1: 1, 2: 2])
  }

  @Test func aTitleChangeCausesNoRetile() async {
    let (_, backend) = makeStarted(windows: spread(1, 2))
    let current = backend.windows[0]
    var renamed = current
    renamed.title = "new title"
    backend.send(.updated(renamed))
    await settle()
    #expect(backend.moves.isEmpty)
  }

  @Test func theOperatingSystemFocusingATiledWindowUpdatesTheFocus() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    backend.send(.focused(WindowID(3)))
    await settle()
    _ = manager.swap(.main)
    // Window 3 had focus, so it is the one that moved to the master slot.
    #expect(slots(manager)[3] == 1)
  }

  @Test func focusingAnUntiledWindowDoesNotChangeTheFocusedTile() async {
    let windows = spread(1, 2) + [makeWindow(id: 7, kind: .dialog)]
    let (manager, backend) = makeStarted(windows: windows)
    backend.send(.focused(WindowID(2)))
    backend.send(.focused(WindowID(7)))
    await settle()
    _ = manager.swap(.main)
    #expect(slots(manager)[2] == 1, "swap is relative to the last tiled window you used")
  }

  // MARK: - Applying layouts

  @Test func windowsAlreadyInPlaceAreNotMovedAgain() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    // The manager learns the new frames from the backend's `updated` events, which arrive
    // asynchronously; wait for them, otherwise it still sees the old frames.
    await settle()
    // Everything is already in its slot, so a layout change that yields the same frames is free.
    _ = manager.setLayout(.set(.tall))
    #expect(backend.moves.isEmpty)
  }

  @Test func retileMovesEveryWindowEvenIfItLooksInPlace() {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    #expect(manager.retile() == .ok)
    #expect(backend.moves.map(\.id.rawValue).sorted() == [1, 2])
  }

  @Test func retilePutsAWindowYouDraggedBackIntoItsSlot() async {
    let (manager, backend) = makeStarted(windows: spread(1, 2))
    backend.send(
      .updated(makeWindow(id: 1, frame: CGRect(x: 900, y: 700, width: 200, height: 100))))
    await settle()
    #expect(backend.moves.isEmpty)
    _ = manager.retile()
    #expect(frame(of: 1, in: backend)?.minX == area.minX)
  }

  @Test func oneWindowFailingDoesNotStopTheOthersAndIsReported() {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    backend.failingMoves = [WindowID(2)]
    let response = manager.retile()
    #expect(response == .message("1 window could not be placed"))
    #expect(Set(backend.moves.map(\.id.rawValue)) == [1, 3])
  }

  @Test func severalFailuresArePluralised() {
    let (manager, backend) = makeStarted(windows: spread(1, 2, 3))
    backend.failingMoves = [WindowID(1), WindowID(2)]
    #expect(manager.retile() == .message("2 windows could not be placed"))
  }
}

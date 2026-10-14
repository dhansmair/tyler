import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// Focus follows the mouse once the pointer rests. Windows 1, 2 and 3 tile `tall` on the fake
/// display: window 1 on the left, 2 above 3 on the right. Window 1 has focus.
@Suite("Focus follows mouse")
@MainActor
struct FocusFollowsMouseScenarios {
  private static let overWindow1 = CGPoint(x: 400, y: 600)
  private static let overWindow2 = CGPoint(x: 1300, y: 300)
  private static let overWindow3 = CGPoint(x: 1300, y: 900)

  private let pointer = FakePointer()
  private let stacking = FakeStacking()
  private let clock = TestClock()

  private func makeHarness(
    _ ids: [UInt32] = [1, 2, 3], config: Config = Self.following, configFile: FakeConfigFile? = nil,
    animator: Animator = .snap
  ) async -> ManagerHarness {
    let harness = ManagerHarness(
      ids, animator: animator, config: config, configFile: configFile, pointer: pointer,
      stacking: stacking, clock: clock)
    await harness.osFocus(1)
    harness.windowSystem.clearRecordedCalls()
    return harness
  }

  private static var following: Config {
    var config = Config()
    config.mouse.focusFollows = true
    return config
  }

  /// Moves the pointer to `location` and lets `milliseconds` pass.
  private func move(
    to location: CGPoint, thenWait milliseconds: Int = 100, in harness: ManagerHarness
  ) async {
    pointer.move(to: location)
    await harness.settle()
    await wait(milliseconds, in: harness)
  }

  private func wait(_ milliseconds: Int, in harness: ManagerHarness) async {
    clock.advance(by: .milliseconds(milliseconds))
    await harness.settle()
  }

  @Test func aRestFocusesTheWindowUnderThePointer() async {
    let harness = await makeHarness()
    await move(to: Self.overWindow2, thenWait: 99, in: harness)
    #expect(harness.windowSystem.focusCalls.isEmpty, "the pointer hasn't rested long enough")
    await wait(1, in: harness)
    #expect(harness.windowSystem.focusCalls == [WindowID(2)])
  }

  @Test func theDelayComesFromTheConfig() async {
    var config = Self.following
    config.mouse.focusDelay = 300
    let harness = await makeHarness(config: config)
    await move(to: Self.overWindow2, thenWait: 299, in: harness)
    #expect(harness.windowSystem.focusCalls.isEmpty)
    await wait(1, in: harness)
    #expect(harness.windowSystem.focusCalls == [WindowID(2)])
  }

  @Test func onlyTheLastMoveCounts() async {
    let harness = await makeHarness()
    await move(to: Self.overWindow2, thenWait: 60, in: harness)
    await move(to: Self.overWindow3, thenWait: 60, in: harness)
    #expect(harness.windowSystem.focusCalls.isEmpty, "the pointer swept on before resting")
    await wait(40, in: harness)
    #expect(harness.windowSystem.focusCalls == [WindowID(3)])
    #expect(stacking.queries == [Self.overWindow3], "nothing is looked up before a rest")
  }

  @Test func theFocusEventThatFollowsIsTylersOwn() async {
    let harness = await makeHarness()
    await move(to: Self.overWindow2, in: harness)
    #expect(harness.manager.interpreter.expectedFocus == [WindowID(2)])
    await harness.osFocus(2)
    #expect(harness.manager.interpreter.expectedFocus.isEmpty)
  }

  @Test func theFocusedWindowIsLeftAlone() async {
    let harness = await makeHarness()
    await move(to: Self.overWindow1, in: harness)
    #expect(harness.windowSystem.focusCalls.isEmpty)
  }

  @Test func aFloatInFrontOfATiledWindowGetsTheFocus() async {
    let harness = await makeHarness([1, 2, 3, 9])
    await harness.osFocus(9)
    #expect(harness.manager.setFloat(.toggle) == .ok)
    await harness.windowSystem.userMoves(9, to: CGRect(x: 1200, y: 200, width: 300, height: 200))
    await harness.osFocus(1)
    harness.windowSystem.clearRecordedCalls()
    stacking.front = [9]
    await move(to: CGPoint(x: 1300, y: 300), in: harness)
    #expect(harness.windowSystem.focusCalls == [WindowID(9)])
  }

  @Test func aParkedWindowsSliverNeverTakesTheFocus() async {
    let harness = await makeHarness()
    _ = harness.manager.moveToWorkspace(.number(2), follow: false)
    #expect(harness.isParked(1))
    await harness.osFocus(2)
    stacking.front = [1]
    let edge = CGPoint(x: (harness.frame(of: 1)?.minX ?? 0) + 0.5, y: 600)
    #expect(stacking.topmostWindow(at: edge) == StackedWindow(id: WindowID(1), layer: 0))
    harness.windowSystem.clearRecordedCalls()
    await move(to: edge, in: harness)
    #expect(harness.windowSystem.focusCalls.isEmpty)
    #expect(harness.manager.workspaces.currentIndex == 0)
  }

  @Test func aStripWindowOutOfViewNeverTakesTheFocus() async {
    let harness = await makeHarness()
    _ = harness.manager.setLayout(.set(.strip))
    await harness.settle()
    #expect(harness.isParked(3))
    stacking.front = [3]
    let edge = CGPoint(x: (harness.frame(of: 3)?.minX ?? 0) + 0.5, y: 600)
    harness.windowSystem.clearRecordedCalls()
    await move(to: edge, in: harness)
    #expect(harness.windowSystem.focusCalls.isEmpty)
    #expect(harness.isParked(3), "the strip didn't scroll")
  }

  /// The fake display's Dock is on the left, 55 points wide, and the menu bar 38 points high.
  @Test(arguments: [CGPoint(x: 20, y: 600), CGPoint(x: 1300, y: 20)])
  func aFloatUnderTheDockOrTheMenuBarIsLeftAlone(at location: CGPoint) async {
    let harness = await makeHarness([1, 2, 9])
    await harness.osFocus(9)
    #expect(harness.manager.setFloat(.toggle) == .ok)
    await harness.windowSystem.userMoves(9, to: CGRect(x: 0, y: 0, width: 1800, height: 1169))
    await harness.osFocus(1)
    harness.windowSystem.clearRecordedCalls()
    stacking.front = [9]
    await move(to: location, in: harness)
    #expect(harness.windowSystem.focusCalls.isEmpty)
    await move(to: Self.overWindow2, in: harness)
    #expect(harness.windowSystem.focusCalls == [WindowID(9)], "inside the visible frame it counts")
  }

  enum Obstacle: CaseIterable, Sendable {
    case buttonHeld, tilingOff, menuOpen, overTheDock, swipe
  }

  @Test(arguments: Obstacle.allCases)
  func nothingIsFocusedWhile(_ obstacle: Obstacle) async {
    let harness = await makeHarness()
    pointer.move(to: Self.overWindow2)
    await harness.settle()
    switch obstacle {
    case .buttonHeld: pointer.isPrimaryButtonDown = true
    case .tilingOff: _ = harness.manager.setTiling(.off)
    case .menuOpen: stacking.isMenuOpen = true
    case .overTheDock:
      stacking.overlays = [
        (StackedWindow(id: WindowID(500), layer: 20), CGRect(x: 0, y: 0, width: 1800, height: 1169))
      ]
    case .swipe: pointer.swipe(.began)
    }
    await harness.settle()
    harness.windowSystem.clearRecordedCalls()
    await wait(100, in: harness)
    #expect(harness.windowSystem.focusCalls.isEmpty)
  }

  @Test func whenOffMovesAreNotEvenWatched() async {
    let harness = await makeHarness(config: Config())
    #expect(!pointer.watchesMoves)
    await move(to: Self.overWindow2, in: harness)
    #expect(stacking.queries.isEmpty)
  }

  @Test func aStillPointerKeepsTheKeyboardsFocus() async {
    let harness = await makeHarness([1, 2])
    await move(to: Self.overWindow2, in: harness)
    #expect(harness.windowSystem.focusCalls == [WindowID(2)])
    await harness.osFocus(2)
    #expect(harness.manager.focus(.prev) == .ok)
    _ = harness.manager.switchWorkspace(.next)
    _ = harness.manager.switchWorkspace(.prev)
    await harness.settle()
    harness.windowSystem.clearRecordedCalls()
    await wait(1000, in: harness)
    #expect(harness.windowSystem.focusCalls.isEmpty, "only movement moves the focus")
  }

  @Test func reloadTurnsItOnAndOff() async {
    let file = FakeConfigFile(.config(Config()))
    let harness = await makeHarness(config: Config(), configFile: file)
    #expect(!pointer.watchesMoves)
    file.write(.config(Self.following))
    _ = harness.manager.reload()
    #expect(pointer.watchesMoves)

    pointer.move(to: Self.overWindow2)
    await harness.settle()
    file.write(.config(Config()))
    _ = harness.manager.reload()
    #expect(!pointer.watchesMoves)
    await wait(100, in: harness)
    #expect(harness.windowSystem.focusCalls.isEmpty, "the waiting focus was dropped")
  }
}

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

  private func makeScenario(
    _ ids: [UInt32] = [1, 2, 3], config: Config = Self.following, configFile: FakeConfigFile? = nil
  ) async -> Scenario {
    let scenario = await Scenario(
      openAtStart: spread(ids), config: config, configFile: configFile)
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    return scenario
  }

  private static var following: Config { config(followingFocus: true) }

  /// Window 1 focused on display 1, and an empty workspace on display 2.
  private func besideAnEmptyDisplay(config: Config = Self.following) async -> Scenario {
    let scenario = await Scenario(
      displays: [FakeDisplays.main, FakeDisplays.secondary], workspaces: [1: [1]], config: config)
    await scenario.focus(1)
    return scenario
  }

  private static let onEmptyDisplay = CGPoint(
    x: FakeDisplays.secondary.visibleFrame.midX, y: FakeDisplays.secondary.visibleFrame.midY)

  @Test func aRestOnAnEmptyDisplayFocusesThatDisplay() async {
    let scenario = await besideAnEmptyDisplay()
    await scenario.movePointer(to: Self.onEmptyDisplay)
    #expect(scenario.focusedDisplay == 2)
  }

  /// The keys stay with the window until another one takes them.
  @Test func aRestOnAnEmptyDisplayLeavesTheFocusedWindow() async {
    let scenario = await besideAnEmptyDisplay()
    let focusCalls = scenario.windowSystem.focusCalls.count
    await scenario.movePointer(to: Self.onEmptyDisplay)
    #expect(scenario.windowSystem.focusCalls.count == focusCalls)
    #expect(scenario.windowSystem.unfocusCount == 0)
  }

  @Test func aWindowOpenedAfterARestOnAnEmptyDisplayGoesThere() async {
    let scenario = await besideAnEmptyDisplay()
    await scenario.movePointer(to: Self.onEmptyDisplay)
    await scenario.open(
      makeWindow(id: 9, frame: FakeDisplays.main.visibleFrame.insetBy(dx: 50, dy: 50)))
    #expect(scenario.list(5) == [9])
  }

  @Test func withoutFocusFollowsARestLeavesTheFocusedDisplay() async {
    let scenario = await besideAnEmptyDisplay(config: Self.config(followingFocus: false))
    await scenario.movePointer(to: Self.onEmptyDisplay)
    #expect(scenario.focusedDisplay == 1)
  }

  @Test func aRestWithTheButtonDownLeavesTheFocusedDisplay() async {
    let scenario = await besideAnEmptyDisplay()
    scenario.pointer.isPrimaryButtonDown = true
    await scenario.movePointer(to: Self.onEmptyDisplay)
    #expect(scenario.focusedDisplay == 1)
  }

  /// Without the resize cursor over gaps, which watches the pointer's moves too.
  private static func config(followingFocus: Bool) -> Config {
    var config = Config()
    config.mouse.focusFollows = followingFocus
    config.mouse.gapResize = false
    return config
  }

  /// Moves the pointer to `location` and lets `milliseconds` pass.
  private func move(
    to location: CGPoint, thenWait milliseconds: Int = 100, in scenario: Scenario
  ) async {
    scenario.pointer.move(to: location)
    await scenario.harness.settle()
    await scenario.wait(.milliseconds(milliseconds))
  }

  /// Floats window 9 and lays it over `frame`, with window 1 focused.
  private func float(_ scenario: Scenario, over frame: CGRect) async {
    await scenario.focus(9)
    #expect(await scenario.command("window float toggle") == .ok)
    await scenario.moveByHand(9, to: frame)
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()
    scenario.stacking.front = [9]
  }

  @Test func aRestFocusesTheWindowUnderThePointer() async {
    let scenario = await makeScenario()
    await move(to: Self.overWindow2, thenWait: 99, in: scenario)
    #expect(scenario.windowSystem.focusCalls.isEmpty, "the pointer hasn't rested long enough")
    await scenario.wait(.milliseconds(1))
    #expect(scenario.windowSystem.focusCalls == [WindowID(2)])
  }

  @Test func theDelayComesFromTheConfig() async {
    var config = Self.following
    config.mouse.focusDelay = 300
    let scenario = await makeScenario(config: config)
    await move(to: Self.overWindow2, thenWait: 299, in: scenario)
    #expect(scenario.windowSystem.focusCalls.isEmpty)
    await scenario.wait(.milliseconds(1))
    #expect(scenario.windowSystem.focusCalls == [WindowID(2)])
  }

  @Test func onlyTheLastMoveCounts() async {
    let scenario = await makeScenario()
    await move(to: Self.overWindow2, thenWait: 60, in: scenario)
    await move(to: Self.overWindow3, thenWait: 60, in: scenario)
    #expect(scenario.windowSystem.focusCalls.isEmpty, "the pointer swept on before resting")
    await scenario.wait(.milliseconds(40))
    #expect(scenario.windowSystem.focusCalls == [WindowID(3)])
    #expect(scenario.stacking.queries == [Self.overWindow3], "nothing is looked up before a rest")
  }

  @Test func theFocusEventThatFollowsIsTylersOwn() async {
    let scenario = await makeScenario()
    await move(to: Self.overWindow2, in: scenario)
    await scenario.command("workspace focus next")
    await scenario.focus(2)
    #expect(scenario.shown == [2], "macOS reporting the focus late doesn't switch back")
  }

  @Test func theFocusedWindowIsLeftAlone() async {
    let scenario = await makeScenario()
    await move(to: Self.overWindow1, in: scenario)
    #expect(scenario.windowSystem.focusCalls.isEmpty)
  }

  @Test func aFloatInFrontOfATiledWindowGetsTheFocus() async {
    let scenario = await makeScenario([1, 2, 3, 9])
    await float(scenario, over: CGRect(x: 1200, y: 200, width: 300, height: 200))
    await move(to: CGPoint(x: 1300, y: 300), in: scenario)
    #expect(scenario.windowSystem.focusCalls == [WindowID(9)])
  }

  @Test func aParkedWindowsSliverNeverTakesTheFocus() async {
    let scenario = await makeScenario()
    await scenario.command("window move-to-workspace 2")
    #expect(scenario.isParked(1))
    await scenario.focus(2)
    scenario.stacking.front = [1]
    let edge = CGPoint(x: (scenario.frame(of: 1)?.minX ?? 0) + 0.5, y: 600)
    #expect(scenario.stacking.topmostWindow(at: edge) == StackedWindow(id: WindowID(1), layer: 0))
    scenario.windowSystem.clearRecordedCalls()
    await move(to: edge, in: scenario)
    #expect(scenario.windowSystem.focusCalls.isEmpty)
    #expect(scenario.shown == [1])
  }

  @Test func aStripWindowOutOfViewNeverTakesTheFocus() async {
    let scenario = await makeScenario()
    await scenario.command("layout set strip")
    #expect(scenario.isParked(3))
    scenario.stacking.front = [3]
    let edge = CGPoint(x: (scenario.frame(of: 3)?.minX ?? 0) + 0.5, y: 600)
    scenario.windowSystem.clearRecordedCalls()
    await move(to: edge, in: scenario)
    #expect(scenario.windowSystem.focusCalls.isEmpty)
    #expect(scenario.isParked(3), "the strip didn't scroll")
  }

  /// The fake display's Dock is on the left, 55 points wide, and the menu bar 38 points high.
  @Test(arguments: [CGPoint(x: 20, y: 600), CGPoint(x: 1300, y: 20)])
  func aFloatUnderTheDockOrTheMenuBarIsLeftAlone(at location: CGPoint) async {
    let scenario = await makeScenario([1, 2, 9])
    await float(scenario, over: CGRect(x: 0, y: 0, width: 1800, height: 1169))
    await move(to: location, in: scenario)
    #expect(scenario.windowSystem.focusCalls.isEmpty)
    await move(to: Self.overWindow2, in: scenario)
    #expect(scenario.windowSystem.focusCalls == [WindowID(9)], "inside the visible frame it counts")
  }

  enum Obstacle: CaseIterable, Sendable {
    case buttonHeld, tilingOff, menuOpen, overTheDock, swipe
  }

  @Test(arguments: Obstacle.allCases)
  func nothingIsFocusedWhile(_ obstacle: Obstacle) async {
    let scenario = await makeScenario()
    scenario.pointer.move(to: Self.overWindow2)
    await scenario.harness.settle()
    switch obstacle {
    case .buttonHeld: scenario.pointer.isPrimaryButtonDown = true
    case .tilingOff: await scenario.start("tiling off")
    case .menuOpen: scenario.stacking.isMenuOpen = true
    case .overTheDock:
      scenario.stacking.overlays = [
        (StackedWindow(id: WindowID(500), layer: 20), CGRect(x: 0, y: 0, width: 1800, height: 1169))
      ]
    case .swipe: scenario.pointer.swipe(.began)
    }
    await scenario.harness.settle()
    scenario.windowSystem.clearRecordedCalls()
    await scenario.wait(.milliseconds(100))
    #expect(scenario.windowSystem.focusCalls.isEmpty)
  }

  @Test func whenOffMovesAreNotEvenWatched() async {
    let scenario = await makeScenario(config: Self.config(followingFocus: false))
    #expect(!scenario.pointer.watchesMoves)
    await move(to: Self.overWindow2, in: scenario)
    #expect(scenario.stacking.queries.isEmpty)
  }

  @Test func aStillPointerKeepsTheKeyboardsFocus() async {
    let scenario = await makeScenario([1, 2])
    await move(to: Self.overWindow2, in: scenario)
    #expect(scenario.windowSystem.focusCalls == [WindowID(2)])
    await scenario.focus(2)
    #expect(await scenario.command("window focus prev") == .ok)
    await scenario.command("workspace focus next")
    await scenario.command("workspace focus prev")
    scenario.windowSystem.clearRecordedCalls()
    await scenario.wait(.milliseconds(1000))
    #expect(scenario.windowSystem.focusCalls.isEmpty, "only movement moves the focus")
  }

  @Test func reloadTurnsItOnAndOff() async {
    let file = FakeConfigFile(.config(Self.config(followingFocus: false)))
    let scenario = await makeScenario(config: Self.config(followingFocus: false), configFile: file)
    #expect(!scenario.pointer.watchesMoves)
    file.write(.config(Self.following))
    await scenario.command("config reload")
    #expect(scenario.pointer.watchesMoves)

    scenario.pointer.move(to: Self.overWindow2)
    await scenario.harness.settle()
    file.write(.config(Self.config(followingFocus: false)))
    await scenario.start("config reload")
    #expect(!scenario.pointer.watchesMoves)
    await scenario.wait(.milliseconds(100))
    #expect(scenario.windowSystem.focusCalls.isEmpty, "the waiting focus was dropped")
  }
}

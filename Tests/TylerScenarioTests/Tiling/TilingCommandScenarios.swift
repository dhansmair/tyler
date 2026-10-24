import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerProtocol
import TylerTestSupport

@testable import TylerServer

@Suite("Tiling: commands")
@MainActor
struct TilingCommandScenarios {
  // MARK: - Focus and swap commands

  @Test func focusNextFocusesTheNextTiledWindow() async {
    let scenario = await Scenario(openAtStart: spread([1, 2, 3]))
    await scenario.command("window focus master")
    scenario.windowSystem.clearRecordedCalls()
    #expect(await scenario.command("window focus next") == .ok)
    #expect(scenario.windowSystem.focusCalls == [WindowID(2)])
    #expect(await scenario.command("window focus next") == .ok)
    #expect(scenario.windowSystem.focusCalls == [WindowID(2), WindowID(3)])
  }

  @Test func focusWrapsAroundAndCanJumpToTheMain() async {
    let scenario = await Scenario(openAtStart: spread([1, 2, 3]))
    await scenario.command("window focus prev")  // nothing focused yet: the last window
    await scenario.command("window focus next")  // wraps to the first
    await scenario.command("window focus prev")  // back to the last
    await scenario.command("window focus master")
    #expect(scenario.windowSystem.focusCalls == [3, 1, 3, 1].map(WindowID.init))
  }

  @Test func aFailedFocusIsReportedAsAnError() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    scenario.windowSystem.failingFocus = [WindowID(1)]
    guard case .error(let message) = await scenario.command("window focus master") else {
      Issue.record("expected an error")
      return
    }
    #expect(message.contains("cannot focus"))
  }

  @Test func focusOnNoTiledWindowsIsAnError() async {
    let scenario = await Scenario(workspaces: [:])
    #expect(await scenario.command("window focus next") == .error("no tiled windows"))
  }

  @Test func swapReordersAndRetiles() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(1)
    scenario.windowSystem.clearRecordedCalls()

    #expect(await scenario.command("window swap next") == .ok)
    #expect(scenario.list(1) == [2, 1, 3])
    // Windows 1 and 2 traded slots, so both had to move.
    #expect(Set(scenario.windowSystem.moves.map(\.id.rawValue)) == [1, 2])
  }

  @Test func swapMainBringsTheFocusedWindowToTheMainSlot() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(3)
    await scenario.command("window swap master")
    #expect(scenario.list(1) == [3, 2, 1])
  }

  @Test func swapNeedsTwoWindows() async {
    let scenario = await Scenario(workspaces: [1: [1]])
    #expect(
      await scenario.command("window swap next")
        == .error("need at least two tiled windows to swap"))
  }

  @Test func swapNeedsAFocusedTiledWindow() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    #expect(await scenario.command("window swap next") == .error("no tiled window is focused"))
  }

  // MARK: - Layout and ratio

  @Test func layoutFullGivesEveryWindowTheWholeArea() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    #expect(await scenario.command("layout set full") == .message("layout full"))
    for windowID: UInt32 in [1, 2, 3] {
      #expect(scenario.frame(of: windowID) == scenario.rect(.full))
    }
  }

  @Test func layoutNextLeavesOutTheStripByDefault() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    var names: [Response] = []
    for _ in 1...3 { names.append(await scenario.command("layout next")) }
    #expect(names == ["grid", "full", "tall"].map { .message("layout \($0)") })
  }

  @Test func layoutNextFollowsTheConfiguredCycle() async {
    let config = Config(layouts: Config.Layouts(cycle: [.strip, .tall]))
    let scenario = await Scenario(workspaces: [1: [1, 2]], config: config)
    #expect(await scenario.command("layout next") == .message("layout strip"))
    #expect(await scenario.command("layout next") == .message("layout tall"))
    // A layout chosen by name, outside the cycle, goes on to the cycle's first.
    await scenario.command("layout set full")
    #expect(await scenario.command("layout next") == .message("layout strip"))
  }

  @Test func ratioMovesTheDividerAndStopsAtItsLimit() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    let before = scenario.frame(of: 1)?.width ?? 0
    #expect(await scenario.command("layout ratio +0.1") == .ok)
    #expect((scenario.frame(of: 1)?.width ?? 0) > before)

    await scenario.command("layout ratio +0.9")  // clamps to the maximum
    scenario.windowSystem.clearRecordedCalls()
    guard case .message(let text) = await scenario.command("layout ratio +0.05") else {
      Issue.record("expected a message at the limit")
      return
    }
    #expect(text.contains("already at its limit"))
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  // MARK: - Floating

  @Test func floatingTheFocusedWindowRemovesItFromTheListAndRetilesTheRest() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(2)
    #expect(await scenario.command("window float toggle") == .ok)
    #expect(scenario.list(1) == [1, 3])
    let floatedWindow = scenario.windowList.first { $0.id == WindowID(2) }
    #expect(floatedWindow?.isFloated == true)
    #expect(floatedWindow?.slot == nil)
  }

  @Test func aFloatedWindowIsNotMovedByLaterRetiles() async {
    let scenario = await Scenario(workspaces: [1: [1, 2, 3]])
    await scenario.focus(2)
    await scenario.command("window float toggle")
    scenario.windowSystem.clearRecordedCalls()
    await scenario.command("workspace retile")
    #expect(!scenario.windowSystem.moves.map(\.id.rawValue).contains(2))
  }

  @Test func floatingTwiceTilesTheWindowAgain() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    await scenario.command("window float toggle")
    #expect(scenario.list(1) == [1])
    // A floated window can still be focused by the user and toggled back.
    #expect(await scenario.command("window float toggle") == .ok)
    #expect(scenario.list(1) == [1, 2])
  }

  @Test func floatOnAndOffSetTheStateWhateverItWas() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    #expect(await scenario.command("window float on") == .ok)
    #expect(scenario.list(1) == [1])
    #expect(await scenario.command("window float on") == .message("already floating"))
    #expect(scenario.list(1) == [1])
    #expect(await scenario.command("window float off") == .ok)
    #expect(scenario.list(1) == [1, 2])
    #expect(await scenario.command("window float off") == .message("already tiled"))
    #expect(scenario.list(1) == [1, 2])
  }

  @Test(arguments: ["on", "off", "toggle"])
  func windowsThatAreNeverTiledCannotBeFloatedOrTiled(mode: String) async {
    let scenario = await Scenario(openAtStart: spread([1]) + [makeWindow(id: 8, kind: .dialog)])
    await scenario.focus(8)
    #expect(
      await scenario.command("window float \(mode)")
        == .error("this window is never tiled, so it can't be floated"))
  }

  @Test func floatNeedsAFocusedWindow() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]))
    #expect(await scenario.command("window float toggle") == .error("no focused window"))
  }

  @Test func aDestroyedWindowIsForgottenByTheFloatedSet() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.focus(2)
    await scenario.command("window float toggle")
    await scenario.close(2)
    // The window id comes back (ids can be reused); it must tile like a new window.
    await scenario.open(makeWindow(id: 2, frame: CGRect(x: 300, y: 100, width: 300, height: 200)))
    #expect(scenario.list(1).contains(2))
  }

  // MARK: - Tiling on and off

  @Test func tilingOffBlocksEveryWorkspaceCommand() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    #expect(await scenario.command("tiling off") == .message("tiling off"))
    for command in [
      "workspace retile", "window focus next", "window swap next", "layout next",
      "layout ratio +0.05", "window float toggle",
    ] {
      #expect(await scenario.command(command) == .error(WindowManager.tilingOffMessage))
    }
  }

  @Test func tilingOffLeavesWindowsAloneWhenThingsChange() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.command("tiling off")
    scenario.windowSystem.clearRecordedCalls()
    await scenario.open(makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200)))
    await scenario.close(1)
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func tilingOffStillAnswersListAndTilingItself() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.command("tiling off")
    #expect(!scenario.windowList.isEmpty)
    #expect(await scenario.command("tiling toggle") == .message("tiling on"))
  }

  @Test func turningTilingBackOnTilesEverythingThatIsEligibleNow() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.command("tiling off")
    await scenario.open(makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200)))
    scenario.windowSystem.clearRecordedCalls()

    #expect(await scenario.command("tiling on") == .message("tiling on"))
    #expect(scenario.list(1).count == 3)
    #expect(!scenario.windowSystem.moves.isEmpty)
  }

  @Test func turningTilingOnSaysWhichWindowsItCouldNotPlace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    await scenario.command("tiling off")
    scenario.windowSystem.failingMoves = [WindowID(2)]
    #expect(
      await scenario.command("tiling on") == .message("tiling on; 1 window could not be placed"))
  }

  @Test func turningTilingOnWhenAlreadyOnDoesNotMoveAnything() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    scenario.windowSystem.clearRecordedCalls()
    #expect(await scenario.command("tiling on") == .message("tiling on"))
    #expect(scenario.windowSystem.moves.isEmpty)
  }

  @Test func turningTilingOnKeepsTheOrderOfWindowsAlreadyInTheList() async {
    let scenario = await Scenario(workspaces: [1: [3, 2, 1]])
    await scenario.command("tiling off")
    await scenario.command("tiling on")
    #expect(scenario.list(1) == [3, 2, 1])
  }

  // MARK: - Permission

  @Test func commandsWithoutPermissionExplainWhatToDo() async {
    let scenario = await Scenario(workspaces: [:], gate: FakeGate(isTrusted: false))
    for command in [
      "workspace retile", "window focus next", "window swap next", "layout next",
      "layout ratio +0.05", "window float toggle",
    ] {
      #expect(await scenario.command(command) == .error(WindowManager.permissionMessage))
    }
  }

  @Test(arguments: [("on", "tiling on"), ("off", "tiling off")])
  func tilingWithoutPermissionSaysItWaits(mode: String, reply: String) async {
    let scenario = await Scenario(workspaces: [:], gate: FakeGate(isTrusted: false))
    let expected =
      "\(reply) once Accessibility permission is granted\n\(WindowManager.permissionMessage)"
    #expect(await scenario.command("tiling \(mode)") == .message(expected))
  }

  @Test func tilingOffBeforePermissionLeavesWindowsAloneOnceGranted() async {
    let scenario = await Scenario(
      openAtStart: spread([1, 2]), gate: FakeGate(isTrusted: false))
    await scenario.command("tiling off")
    await scenario.grantPermission()
    #expect(scenario.windowSystem.moves.isEmpty)
    #expect(
      await scenario.command("workspace retile") == .error(WindowManager.tilingOffMessage))
  }

  @Test func everyKindOfRequestReachesItsCommand() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]])
    #expect(await scenario.command("ping") == .pong)
    #expect(await scenario.command("tiling off") == .message("tiling off"))
    #expect(
      await scenario.command("workspace retile") == .error(WindowManager.tilingOffMessage))
    #expect(await scenario.command("tiling on") == .message("tiling on"))
    #expect(await scenario.command("layout set full") == .message("layout full"))
    #expect(await scenario.command("layout ratio +0.05") == .ok)
  }
}

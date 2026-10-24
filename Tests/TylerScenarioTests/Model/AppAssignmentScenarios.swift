import CoreGraphics
import Testing
import TylerConfig
import TylerCore
import TylerTestSupport

@Suite("Workspaces: app assignments")
@MainActor
struct AppAssignmentScenarios {
  /// Firefox goes to workspace 3.
  private let config = Config(apps: ["firefox": Config.App(workspace: 3)])

  private func firefox(id: UInt32, isFocused: Bool = false) -> WindowInfo {
    var window = makeWindow(
      id: id, frame: CGRect(x: 700, y: 100, width: 300, height: 200), isFocused: isFocused)
    window.appName = "Firefox"
    window.bundleID = "org.mozilla.firefox"
    return window
  }

  @Test func windowsOpenAtStartGoToTheirWorkspace() async {
    let scenario = await Scenario(openAtStart: spread([1, 2]) + [firefox(id: 9)], config: config)
    #expect(scenario.workspaces == [1: 1, 2: 1, 9: 3])
    #expect(scenario.isParked(9))
    #expect(
      [scenario.frame(of: 1), scenario.frame(of: 2)]
        == [scenario.rect(.leftHalf), scenario.rect(.rightHalf)])
  }

  @Test func aNewWindowInTheBackgroundIsParkedAndTheViewStays() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]], config: config)
    scenario.windowSystem.clearRecordedCalls()
    await scenario.open(firefox(id: 9))

    #expect(scenario.workspaces[9] == 3)
    #expect(scenario.isParked(9))
    #expect(scenario.windowSystem.moves.map(\.id) == [WindowID(9)], "nothing else moved")
    #expect(scenario.shown == [1])
  }

  @Test func focusingTheNewWindowShowsItsWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]], config: config)
    await scenario.open(firefox(id: 9))
    await scenario.focus(9)

    #expect(!scenario.isParked(9))
    #expect(scenario.isParked(1))
    #expect(scenario.shown == [3])
  }

  @Test func aNewWindowFocusedBeforeTylerdSeesItShowsItsWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1, 2]], config: config)
    await scenario.focus(9)
    await scenario.open(firefox(id: 9))

    #expect(scenario.workspaces[9] == 3)
    #expect(!scenario.isParked(9), "the focused window must not be left parked")
    #expect(scenario.isParked(1))
  }

  @Test func anAssignmentToTheCurrentWorkspaceTilesAsUsual() async {
    let scenario = await Scenario(
      workspaces: [1: [1]], config: Config(apps: ["firefox": Config.App(workspace: 1)]))
    await scenario.open(firefox(id: 9))
    #expect(scenario.workspaces == [1: 1, 9: 1])
    #expect(!scenario.isParked(9))
  }

  @Test func otherAppsJoinTheCurrentWorkspace() async {
    let scenario = await Scenario(workspaces: [1: [1]], config: config)
    await scenario.open(makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200)))
    #expect(scenario.workspaces == [1: 1, 9: 1])
  }

  @Test func theBundleIDMatchesToo() async {
    let config = Config(apps: ["org.mozilla.firefox": Config.App(workspace: 2)])
    let scenario = await Scenario(workspaces: [1: [1]], config: config)
    await scenario.open(firefox(id: 9))
    #expect(scenario.workspaces[9] == 2)
  }

  /// Firefox moved by hand to workspace 1 and floated there.
  private func movedAndFloated() async -> Scenario {
    let scenario = await Scenario(openAtStart: spread([1]) + [firefox(id: 9)], config: config)
    await scenario.focus(9)
    await scenario.command("window move-to-workspace 1 --follow")
    #expect(scenario.workspaces[9] == 1)
    await scenario.command("window float toggle")
    #expect(scenario.workspaces[9] == nil)
    return scenario
  }

  @Test func aWindowThatWasTiledBeforeDoesNotJumpBack() async {
    let scenario = await movedAndFloated()
    await scenario.command("window float toggle")
    #expect(scenario.workspaces[9] == 1, "un-floated on the current workspace")
  }

  @Test func aRestartRemembersWhichWindowsWereTiled() async {
    let next = await movedAndFloated().restart(config: config)
    await next.focus(9)
    await next.command("window float toggle")
    #expect(next.workspaces[9] == 1)
  }

  @Test func aClosedWindowsIDIsForgotten() async {
    let scenario = await movedAndFloated()
    await scenario.close(9)
    // Window ids can be reused; a new window with this id is new.
    await scenario.open(firefox(id: 9))
    #expect(scenario.workspaces[9] == 3)
  }
}

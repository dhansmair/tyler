import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

/// Commands act on the focused display. The laptop (`main`, workspaces 1 to 4) holds windows 1
/// and 2; the Dell above it (`secondary`, 5 to 8) holds windows 3 and 4 on workspace 5.
@Suite("Several displays: the focused display")
@MainActor
struct FocusedDisplayTests {
  private let dell = FakeDisplays.secondary

  private func onDell(_ id: UInt32) -> WindowInfo {
    makeWindow(id: id, frame: CGRect(x: 100 + CGFloat(id) * 50, y: -1000, width: 300, height: 200))
  }

  private func harness(config: Config = Config()) -> ManagerHarness {
    ManagerHarness(
      [1, 2], extra: [onDell(3), onDell(4)],
      displays: FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary]),
      config: config)
  }

  private func focusedKey(_ harness: ManagerHarness) -> DisplayKey {
    harness.manager.rows.focusedKey
  }

  private func isParkedOnDell(_ windowID: UInt32, in harness: ManagerHarness) -> Bool {
    guard let frame = harness.frame(of: windowID) else { return false }
    return frame.minX == dell.visibleFrame.maxX - 1 && dell.visibleFrame.contains(frame.origin)
  }

  @Test func aWorkspaceOnTheDellSwitchesThereAndFocusesTheDell() async {
    let harness = harness()
    await harness.osFocus(1)
    #expect(harness.manager.switchWorkspace(.number(6)) == .message("workspace 6"))
    #expect(focusedKey(harness) == dell.key)
    #expect(isParkedOnDell(3, in: harness))
    #expect(isParkedOnDell(4, in: harness))
    #expect(harness.frame(of: 1)?.minX == harness.area.minX, "the laptop stays as it was")
  }

  @Test func prevAndNextStayOnTheFocusedDisplay() async {
    let harness = harness()
    _ = harness.manager.switchWorkspace(.number(6))
    #expect(harness.manager.switchWorkspace(.next) == .message("workspace 7"))
    #expect(harness.manager.switchWorkspace(.prev) == .message("workspace 6"))
    #expect(harness.manager.rows[0].currentIndex == 0, "the laptop still shows 1")
  }

  @Test func anEmptyWorkspaceKeepsItsDisplayFocused() async {
    let harness = harness()
    _ = harness.manager.switchWorkspace(.number(7))
    await harness.settle()
    #expect(focusedKey(harness) == dell.key)
    #expect(harness.manager.switchWorkspace(.prev) == .message("workspace 6"))
  }

  @Test func aWorkspaceOnScreenOnTheDellJustTakesTheFocusThere() async {
    let harness = harness()
    await harness.osFocus(1)
    #expect(harness.manager.switchWorkspace(.number(5)) == .message("workspace 5"))
    #expect(focusedKey(harness) == dell.key)
    #expect(harness.backend.focusCalls.last == WindowID(3))
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func layoutCommandsActOnTheFocusedDisplay() async {
    let harness = harness()
    await harness.osFocus(3)
    #expect(harness.manager.setLayout(.set(.full)) == .message("layout full"))
    #expect(harness.frame(of: 3) == dell.visibleFrame)
    #expect(harness.frame(of: 4) == dell.visibleFrame)
    #expect(harness.manager.rows[0].current.layout == .tall, "the laptop keeps its layout")
  }

  @Test func focusingAWindowFocusesItsDisplay() async {
    let harness = harness()
    await harness.osFocus(4)
    #expect(focusedKey(harness) == dell.key)
    await harness.osFocus(2)
    #expect(focusedKey(harness) == FakeDisplays.main.key)
  }

  @Test func focusingAParkedWindowOnTheDellShowsItsWorkspaceThere() async {
    let harness = harness()
    await harness.osFocus(4)
    _ = harness.manager.moveToWorkspace(.number(6), follow: false)
    await harness.osFocus(1)
    #expect(focusedKey(harness) == FakeDisplays.main.key)

    await harness.osFocus(4)
    #expect(focusedKey(harness) == dell.key)
    #expect(harness.manager.workspaces.number(at: harness.manager.workspaces.currentIndex) == 6)
    #expect(harness.frame(of: 4) == dell.visibleFrame)
    #expect(isParkedOnDell(3, in: harness))
  }

  @Test func aWindowSentToAHiddenWorkspaceOnTheDellParksThere() async {
    let harness = harness()
    await harness.osFocus(2)
    #expect(
      harness.manager.moveToWorkspace(.number(6), follow: false) == .message("moved to workspace 6")
    )
    #expect(harness.workspaces()[2] == 6)
    #expect(isParkedOnDell(2, in: harness))
    #expect(harness.frame(of: 1) == harness.area, "window 1 fills the laptop alone")
    #expect(harness.backend.focusCalls.last == WindowID(1), "focus stays on the laptop")
    #expect(focusedKey(harness) == FakeDisplays.main.key)
  }

  @Test func aWindowSentToTheWorkspaceOnScreenOnTheDellTakesItsSlotThere() async {
    let harness = harness()
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.number(5), follow: false)
    #expect(harness.workspaces()[2] == 5)
    let frame = harness.frame(of: 2) ?? .zero
    #expect(dell.visibleFrame.contains(frame))
  }

  @Test func followingAWindowToTheDellShowsItsWorkspaceThere() async {
    let harness = harness()
    await harness.osFocus(2)
    _ = harness.manager.moveToWorkspace(.number(6), follow: true)
    #expect(focusedKey(harness) == dell.key)
    #expect(harness.frame(of: 2) == dell.visibleFrame)
    #expect(isParkedOnDell(3, in: harness))
    #expect(harness.backend.focusCalls.last == WindowID(2))
  }

  @Test func aFocusedWindowArrivingOnAHiddenWorkspaceOfTheDellShowsItThere() async {
    let harness = harness(config: Config(assignments: ["firefox": 6]))
    var firefox = makeWindow(
      id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200), isFocused: true)
    firefox.appName = "Firefox"
    harness.backend.windows.append(firefox)
    harness.backend.send(.created(firefox))
    await harness.osFocus(9)
    #expect(focusedKey(harness) == dell.key)
    #expect(harness.frame(of: 9) == dell.visibleFrame)
  }

  @Test func theErrorNamesTheWorkspacesOfEveryDisplay() {
    #expect(
      harness().manager.switchWorkspace(.number(9))
        == .error("workspace 9 does not exist (use 1 to 8)"))
  }
}

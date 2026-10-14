import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// The display commands. The laptop (`main`, display 1, workspaces 1 to 4) holds windows 1 and 2;
/// the external display above it (`secondary`, display 2, workspaces 5 to 8) holds windows 3 and 4
/// on workspace 5.
@Suite("Several displays: tyler display")
@MainActor
struct DisplayCommandScenarios {
  private let external = FakeDisplays.secondary

  private func onExternal(_ id: UInt32) -> WindowInfo {
    makeWindow(id: id, frame: CGRect(x: 100 + CGFloat(id) * 50, y: -1000, width: 300, height: 200))
  }

  private func harness() -> ManagerHarness {
    ManagerHarness(
      [1, 2], extra: [onExternal(3), onExternal(4)],
      displays: FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary]))
  }

  private func focusedKey(_ harness: ManagerHarness) -> DisplayKey {
    harness.manager.rows.focusedKey
  }

  @Test func aDisplayByNumberGetsTheFocusAndNothingMoves() async {
    let harness = harness()
    await harness.osFocus(4)
    await harness.osFocus(1)
    harness.backend.clearRecordedCalls()
    #expect(harness.manager.switchDisplay(.number(2)) == .message("display 2"))
    #expect(focusedKey(harness) == external.key)
    #expect(harness.backend.focusCalls == [WindowID(4)], "the window that last had focus there")
    #expect(harness.backend.moves.isEmpty)
  }

  @Test func prevAndNextWrap() async {
    let harness = harness()
    await harness.osFocus(1)
    #expect(harness.manager.switchDisplay(.next) == .message("display 2"))
    #expect(harness.manager.switchDisplay(.next) == .message("display 1"))
    #expect(harness.manager.switchDisplay(.prev) == .message("display 2"))
    #expect(focusedKey(harness) == external.key)
  }

  @Test func theFocusedDisplayIsWhereTheNextCommandGoes() async {
    let harness = harness()
    await harness.osFocus(1)
    _ = harness.manager.switchDisplay(.number(2))
    await harness.settle()
    #expect(harness.manager.switchWorkspace(.next) == .message("workspace 6"))
    #expect(harness.manager.rows[0].currentIndex == 0, "the laptop still shows 1")
  }

  @Test func onAnEmptyWorkspaceNoWindowKeepsTheFocus() async {
    let harness = harness()
    await harness.osFocus(3)
    _ = harness.manager.switchWorkspace(.number(6))
    _ = harness.manager.switchDisplay(.number(1))
    await harness.osFocus(1)
    harness.backend.clearRecordedCalls()

    #expect(harness.manager.switchDisplay(.number(2)) == .message("display 2"))
    #expect(harness.backend.focusCalls.isEmpty)
    #expect(harness.backend.unfocusCount == 1, "keys don't go to the laptop's window")
    #expect(focusedKey(harness) == external.key)
  }

  @Test func aNumberNoDisplayHasIsAnError() {
    #expect(
      harness().manager.switchDisplay(.number(3))
        == .error("display 3 does not exist (use 1 to 2)"))
  }

  @Test func withOneDisplayNextStaysOnIt() async {
    let harness = ManagerHarness([1])
    await harness.osFocus(1)
    #expect(harness.manager.switchDisplay(.next) == .message("display 1"))
    #expect(harness.manager.switchDisplay(.number(2)) == .error("display 2 does not exist (use 1)"))
  }

  @Test func itNeedsTilingOn() {
    let harness = harness()
    _ = harness.manager.setTiling(.off)
    #expect(harness.manager.switchDisplay(.next) == .error(WindowManager.tilingOffMessage))
  }

  @Test func theRequestReachesTheCommand() async {
    let harness = harness()
    #expect(harness.manager.handle(.display(.number(2))) == .message("display 2"))
  }
}

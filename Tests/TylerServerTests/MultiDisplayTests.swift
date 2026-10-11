import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

/// Tiling every display: the laptop (`main`, workspaces 1 to 4) and the Dell above it
/// (`secondary`, workspaces 5 to 8). Windows 1 and 2 start on the laptop, 3 on the Dell.
@Suite("Several displays: tiling each one")
@MainActor
struct MultiDisplayTests {
  private let dell = FakeDisplays.secondary

  private func twoDisplays() -> FakeDisplays {
    FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.secondary])
  }

  private func onDell(_ id: UInt32) -> WindowInfo {
    makeWindow(id: id, frame: CGRect(x: 100, y: -1000, width: 300, height: 200))
  }

  private func harness(config: Config = Config()) -> ManagerHarness {
    ManagerHarness([1, 2], extra: [onDell(3)], displays: twoDisplays(), config: config)
  }

  @Test func eachDisplayTilesItsCurrentWorkspace() {
    let harness = harness()
    #expect(harness.workspaces() == [1: 1, 2: 1, 3: 5])
    let halves = TallLayout().frames(count: 2, in: harness.area)
    #expect([harness.frame(of: 1), harness.frame(of: 2)] == halves)
    #expect(harness.frame(of: 3) == dell.visibleFrame)
  }

  @Test func listShowsEachWindowsDisplayAndWorkspaceNumber() {
    let listed = harness().manager.listed
    let byID = Dictionary(uniqueKeysWithValues: listed.map { ($0.id.rawValue, $0) })
    #expect(byID[1]?.displayNumber == 1)
    #expect(byID[3]?.displayNumber == 2)
    #expect(byID[3]?.workspace == 5)
    #expect(byID[3]?.slot == 1)
  }

  @Test func aWindowAssignedToAHiddenWorkspaceOfTheDellParksAtTheDellsEdge() async {
    let harness = harness(config: Config(assignments: ["firefox": 6]))
    var firefox = makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))
    firefox.appName = "Firefox"
    harness.backend.windows.append(firefox)
    harness.backend.send(.created(firefox))
    await harness.settle()

    #expect(harness.workspaces()[9] == 6)
    #expect(harness.frame(of: 9)?.minX == dell.visibleFrame.maxX - 1)
    #expect(harness.frame(of: 3) == dell.visibleFrame, "workspace 5 stays on screen")
  }

  @Test func tilingOffBringsBackTheParkedWindowsOfEveryDisplay() async {
    let harness = harness(config: Config(assignments: ["firefox": 6]))
    var firefox = makeWindow(id: 9, frame: CGRect(x: 700, y: 100, width: 300, height: 200))
    firefox.appName = "Firefox"
    harness.backend.windows.append(firefox)
    harness.backend.send(.created(firefox))
    await harness.settle()

    #expect(harness.manager.setTiling(.off) == .message("tiling off"))
    #expect(harness.frame(of: 9) == CGRect(x: 700, y: 100, width: 300, height: 200))
    #expect(harness.workspaces()[9] == nil)
  }

  @Test func withADisplayToTheRightTheLaptopParksAtItsLeftEdge() {
    let harness = ManagerHarness(
      [1, 2], displays: FakeDisplays(displays: [FakeDisplays.main, FakeDisplays.right]))
    _ = harness.manager.switchWorkspace(.next)
    for id: UInt32 in [1, 2] {
      #expect(harness.frame(of: id)?.maxX == FakeDisplays.main.visibleFrame.minX + 1)
    }
  }

  @Test func aRestartKeepsTheWorkspacesOfEveryDisplay() async {
    let harness = harness()
    let successor = harness.successor(saved: harness.manager.handOver(), displays: twoDisplays())
    #expect(successor.workspaces() == [1: 1, 2: 1, 3: 5])
    #expect(successor.backend.moves.isEmpty, "every window is already where it belongs")
  }
}

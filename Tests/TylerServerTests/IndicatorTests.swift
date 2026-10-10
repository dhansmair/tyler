import Testing
import TylerCore

@testable import TylerServer

@Suite("Indicator updates")
@MainActor
struct IndicatorTests {
  private let backend = FakeBackend(windows: WorkspaceHarness.spread([1, 2]))
  private let indicator = FakeIndicator()
  private let gate = FakeGate(isTrusted: false)
  private let manager: WindowManager

  init() {
    manager = WindowManager(
      backend: backend, displays: FakeDisplays(), gate: gate, indicator: indicator)
  }

  private var last: IndicatorState? { indicator.shown.last }

  @Test func itShowsTheStateFromTheStartAndWhenPermissionArrives() {
    #expect(indicator.shown.count == 1)
    #expect(last?.tiling == .waitingForPermission)
    gate.isTrusted = true
    manager.startIfPermitted()
    #expect(last?.tiling == .on)
    #expect(last?.title.map(\.text).joined() == "[1] 2 3 4  ▥")
    #expect(last?.workspaces.first?.windowCount == 2)
  }

  @Test func itFollowsSwitchesLayoutsAndTiling() {
    gate.isTrusted = true
    manager.startIfPermitted()
    _ = manager.switchWorkspace(.number(3))
    #expect(last?.title.map(\.text).joined() == "1 2 [3] 4  ▥")
    _ = manager.setLayout(.next)
    #expect(last?.layout == .full)
    _ = manager.setTiling(.off)
    #expect(last?.tiling == .off)
  }

  @Test func itCountsWindowsThatOpenAndClose() async {
    gate.isTrusted = true
    manager.startIfPermitted()
    backend.windows.append(makeWindow(id: 9))
    backend.send(.created(makeWindow(id: 9)))
    for _ in 0..<30 { await Task.yield() }
    #expect(last?.workspaces.first?.windowCount == 3)
    backend.send(.destroyed(WindowID(1)))
    for _ in 0..<30 { await Task.yield() }
    #expect(last?.workspaces.first?.windowCount == 2)
  }

  @Test func itIsNotRedrawnWhenNothingItShowsChanged() async {
    gate.isTrusted = true
    manager.startIfPermitted()
    let count = indicator.shown.count
    _ = manager.focus(.next)
    backend.send(.focused(WindowID(2)))
    for _ in 0..<30 { await Task.yield() }
    _ = manager.switchWorkspace(.number(1))
    #expect(indicator.shown.count == count)
  }
}

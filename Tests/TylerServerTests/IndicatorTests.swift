import Testing
import TylerCore

@testable import TylerServer

@Suite("Indicator updates")
@MainActor
struct IndicatorTests {
  private let backend = FakeBackend(windows: spread([1, 2]))
  private let indicator = FakeIndicator()
  private let gate = FakeGate(isTrusted: false)
  private let manager: WindowManager

  init() {
    manager = WindowManager(
      backend: backend, displays: FakeDisplays(), gate: gate, indicator: indicator)
  }

  private var last: IndicatorSnapshot? { indicator.shown.last }

  @Test func itShowsTheStateFromTheStartAndWhenPermissionArrives() {
    #expect(indicator.shown.count == 1)
    #expect(last?.tiling == .waitingForPermission)
    gate.isTrusted = true
    manager.startIfPermitted()
    #expect(last?.tiling == .on)
    #expect(last?.row.currentIndex == 0)
    #expect(last?.row.count == 4)
    #expect(last?.row[0].count == 2)
  }

  @Test func itFollowsSwitchesLayoutsAndTiling() {
    gate.isTrusted = true
    manager.startIfPermitted()
    _ = manager.switchWorkspace(.number(3))
    #expect(last?.row.currentIndex == 2)
    _ = manager.setLayout(.next)
    #expect(last?.row.current.layout == .full)
    _ = manager.setTiling(.off)
    #expect(last?.tiling == .off)
  }

  @Test func itCountsWindowsThatOpenAndClose() async {
    gate.isTrusted = true
    manager.startIfPermitted()
    backend.windows.append(makeWindow(id: 9))
    backend.send(.created(makeWindow(id: 9)))
    await settle()
    #expect(last?.row[0].count == 3)
    backend.send(.destroyed(WindowID(1)))
    await settle()
    #expect(last?.row[0].count == 2)
  }

  @Test func itIsToldAboutFocusButNotAboutNothing() async {
    gate.isTrusted = true
    manager.startIfPermitted()
    _ = manager.focus(.next)
    backend.send(.focused(WindowID(2)))
    await settle()
    #expect(last?.row.current.focused == WindowID(2))
    let count = indicator.shown.count
    backend.send(.focused(WindowID(2)))
    await settle()
    _ = manager.switchWorkspace(.number(1))
    #expect(indicator.shown.count == count)
  }

  @Test func reloadingTheConfigReachesTheIndicators() {
    let file = FakeConfigFile(.config(Config(indicator: Config.Indicator(text: false))))
    let manager = WindowManager(
      backend: backend, displays: FakeDisplays(), gate: gate, configSource: file.source,
      indicator: indicator)
    #expect(indicator.shown.last?.settings.text == true)
    _ = manager.reload()
    #expect(indicator.shown.last?.settings == Config.Indicator(text: false, map: true))
  }

  @Test func theSnapshotHoldsEachTiledWindowsProcess() {
    gate.isTrusted = true
    manager.startIfPermitted()
    let expected = Dictionary(
      uniqueKeysWithValues: backend.windows.map { ($0.id, $0.processID) })
    #expect(last?.processIDs == expected)
  }

  @Test func theSnapshotHoldsTheDisplaysArea() {
    #expect(last?.area == FakeDisplays().displays.first?.visibleFrame)
  }
}

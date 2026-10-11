import CoreGraphics
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

  @Test func theSnapshotHoldsEachTiledWindowsApp() {
    gate.isTrusted = true
    manager.startIfPermitted()
    let expected = Dictionary(
      uniqueKeysWithValues: backend.windows.map {
        (
          $0.id,
          IndicatorSnapshot.App(processID: $0.processID, name: $0.appName, bundleID: $0.bundleID)
        )
      })
    #expect(last?.apps == expected)
  }

  @Test func theSnapshotHoldsTheDisplaysArea() {
    #expect(last?.area == FakeDisplays().displays.first?.visibleFrame)
  }

  @Test func itShowsTheFocusedDisplaysRowAndFollowsFocusToTheDell() async {
    let dell = FakeDisplays.secondary
    backend.windows.append(
      makeWindow(id: 3, frame: CGRect(x: 100, y: -1000, width: 300, height: 200)))
    let manager = WindowManager(
      backend: backend, displays: FakeDisplays(displays: [FakeDisplays.main, dell]), gate: gate,
      indicator: indicator)
    gate.isTrusted = true
    manager.startIfPermitted()

    backend.send(.focused(WindowID(3)))
    await settle()
    #expect(last?.row.numbers == [5, 6, 7, 8])
    #expect(last?.row.current.windows == [WindowID(3)])
    #expect(last?.area == dell.visibleFrame)

    backend.send(.focused(WindowID(1)))
    await settle()
    #expect(last?.row.numbers == [1, 2, 3, 4])
    #expect(last?.area == FakeDisplays.main.visibleFrame)
  }
}

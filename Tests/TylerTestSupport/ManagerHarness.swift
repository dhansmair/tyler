import CoreGraphics
import TylerConfig
import TylerCore
import TylerRuntime

@testable import TylerServer

/// A started manager over a fake window system, shared by the server suites.
@MainActor
package struct ManagerHarness {
  // Held here because the manager's event pumps only keep it weakly.
  package let manager: WindowManager
  package let windowSystem: FakeWindowSystem
  package let screenLock = FakeScreenLock()
  package let display = FakeDisplays.main
  package var area: CGRect { display.visibleFrame }

  /// A manager over `windows`, started, so the initial tiling has happened, and with recorded
  /// calls cleared unless `clearRecordedCalls` is false. The default animator snaps; pass one
  /// with a `TestClock` to step slides.
  package init(
    windows: [WindowInfo],
    displays: FakeDisplays = FakeDisplays(),
    gate: FakeGate = FakeGate(isTrusted: true),
    animator: Animator = .snap,
    config: Config = Config(),
    configFile: FakeConfigFile? = nil,
    pointer: FakePointer? = nil,
    stacking: FakeStacking? = nil,
    gapCursor: FakeGapCursor? = nil,
    indicator: FakeIndicator? = nil,
    clock: any Clock<Duration> = ContinuousClock(),
    restoring saved: SavedState? = nil,
    clearRecordedCalls: Bool = true
  ) {
    windowSystem = FakeWindowSystem(windows: windows)
    stacking?.windowSystem = windowSystem
    manager = WindowManager(
      windowSystem: windowSystem, displays: displays, gate: gate, screenLock: screenLock,
      animator: animator, config: config,
      configSource: configFile?.source, indicator: indicator, pointer: pointer, stacking: stacking,
      gapCursor: gapCursor, clock: clock,
      logOutput: LogOutput(), restoring: saved)
    manager.startIfPermitted()
    if clearRecordedCalls { windowSystem.clearRecordedCalls() }
  }

  /// Windows `ids` spread left to right on the primary display (see `spread`), plus `extra`.
  package init(
    _ ids: [UInt32],
    extra: [WindowInfo] = [],
    displays: FakeDisplays = FakeDisplays(),
    animator: Animator = .snap,
    config: Config = Config(),
    configFile: FakeConfigFile? = nil,
    pointer: FakePointer? = nil,
    stacking: FakeStacking? = nil,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.init(
      windows: spread(ids) + extra, displays: displays, animator: animator, config: config,
      configFile: configFile, pointer: pointer, stacking: stacking, clock: clock)
  }

  /// The next tylerd after this one handed over `saved`: it finds the windows exactly where this
  /// one left them, without those in `closed`. Its recorded calls are kept, so a test can check
  /// that taking over moved nothing.
  package func successor(
    saved: SavedState?, closing closed: [UInt32] = [], config: Config = Config(),
    displays: FakeDisplays = FakeDisplays()
  ) -> ManagerHarness {
    ManagerHarness(
      windows: windowSystem.windows.filter { !closed.contains($0.id.rawValue) }, displays: displays,
      config: config, restoring: saved, clearRecordedCalls: false)
  }

  /// Where `spread` puts the window at `index`, before tylerd moves it.
  package nonisolated static func originalFrame(index: Int) -> CGRect {
    CGRect(x: 100 + index * 50, y: 100, width: 300, height: 200)
  }

  package func settle() async {
    await TylerTestSupport.settle()
  }

  package func frame(of windowID: UInt32) -> CGRect? {
    windowSystem.frame(of: windowID)
  }

  /// Whether the window waits at the primary display's parking edge, as the manager sees that
  /// display (another display beside it changes the edge).
  package func isParked(_ windowID: UInt32) -> Bool {
    guard let frame = frame(of: windowID) else { return false }
    return frame == Parking.frame(for: frame, on: manager.display(for: display.key) ?? display)
  }

  /// Whether macOS would accept every position tylerd asked for without pulling the window
  /// back on screen (see `Parking`).
  package func everyPositionIsAllowed() -> Bool {
    let positions =
      windowSystem.moves.map { ($0.id, $0.frame.origin) }
      + windowSystem.nudges.map { ($0.id, $0.origin) }
    return positions.allSatisfy { windowID, origin in
      guard let width = frame(of: windowID.rawValue)?.width else { return false }
      return Parking.allowedX(width: width, on: display).contains(origin.x)
        && origin.y >= display.visibleFrame.minY
    }
  }

  /// Window id → 1-based workspace, for windows on a workspace.
  package func workspaces() -> [UInt32: Int] {
    Dictionary(
      uniqueKeysWithValues: manager.listed.compactMap { window in
        window.workspace.map { (window.id.rawValue, $0) }
      })
  }

  /// Focuses `windowID` the way the OS would, and waits for the manager to see it.
  package func osFocus(_ windowID: UInt32) async {
    windowSystem.send(.focused(WindowID(windowID)))
    await settle()
  }
}

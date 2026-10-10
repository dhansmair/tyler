import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

extension Layout {
  /// The frames for `count` windows, as most tests ask for them.
  func frames(
    count: Int, in area: CGRect, parameters: LayoutParameters = LayoutParameters(),
    gaps: LayoutGaps = LayoutGaps()
  ) -> [CGRect] {
    frames(for: LayoutInput(count: count, parameters: parameters), in: area, gaps: gaps)
  }
}

/// Lets the manager's event pumps, and any animation or throttle task, run. Main-actor isolated
/// so the yields happen where those tasks run.
@MainActor
func settle() async {
  for _ in 0..<30 { await Task.yield() }
}

/// Standard windows `ids`, spread left to right on the primary display in that order.
func spread(_ ids: [UInt32]) -> [WindowInfo] {
  ids.enumerated().map { index, windowID in
    makeWindow(id: windowID, frame: ManagerHarness.originalFrame(index: index))
  }
}

extension FakeBackend {
  func frame(of windowID: UInt32) -> CGRect? {
    windows.first { $0.id.rawValue == windowID }?.frame
  }

  /// The user moves or resizes `windowID` to `frame`: the app moves it and reports the new frame.
  func userMoves(_ windowID: UInt32, to frame: CGRect) async {
    guard let index = windows.firstIndex(where: { $0.id.rawValue == windowID }) else {
      Issue.record("no window \(windowID)")
      return
    }
    windows[index].frame = frame
    send(.updated(windows[index]))
    await settle()
  }
}

extension WindowManager {
  /// What `tyler list` would show; empty when it answers with an error.
  var listed: [WindowInfo] {
    guard case .windows(let windows) = windows() else { return [] }
    return windows
  }

  /// Window id → 1-based slot in its workspace's list, for tiled windows.
  var slots: [UInt32: Int] {
    Dictionary(
      uniqueKeysWithValues: listed.compactMap { window in
        window.slot.map { (window.id.rawValue, $0) }
      })
  }
}

/// A started manager over a fake backend, shared by the server suites.
@MainActor
struct ManagerHarness {
  // Held here because the manager's event pumps only keep it weakly.
  let manager: WindowManager
  let backend: FakeBackend
  let display = FakeDisplays.main
  var area: CGRect { display.visibleFrame }

  /// A manager over `windows`, started, so the initial tiling has happened, and with recorded
  /// calls cleared unless `clearRecordedCalls` is false. The default animator snaps; pass one
  /// with a `TestClock` to step slides.
  init(
    windows: [WindowInfo],
    displays: FakeDisplays = FakeDisplays(),
    gate: FakeGate = FakeGate(isTrusted: true),
    animator: Animator = .snap,
    config: Config = Config(),
    configFile: FakeConfigFile? = nil,
    pointer: FakePointer? = nil,
    clock: any Clock<Duration> = ContinuousClock(),
    restoring saved: SavedState? = nil,
    clearRecordedCalls: Bool = true
  ) {
    backend = FakeBackend(windows: windows)
    manager = WindowManager(
      backend: backend, displays: displays, gate: gate, animator: animator, config: config,
      configSource: configFile?.source, pointer: pointer, clock: clock, restoring: saved)
    manager.startIfPermitted()
    if clearRecordedCalls { backend.clearRecordedCalls() }
  }

  /// Windows `ids` spread left to right on the primary display (see `spread`), plus `extra`.
  init(
    _ ids: [UInt32],
    extra: [WindowInfo] = [],
    displays: FakeDisplays = FakeDisplays(),
    animator: Animator = .snap,
    config: Config = Config(),
    configFile: FakeConfigFile? = nil,
    pointer: FakePointer? = nil,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.init(
      windows: spread(ids) + extra, displays: displays, animator: animator, config: config,
      configFile: configFile, pointer: pointer, clock: clock)
  }

  /// The next tylerd after this one handed over `saved`: it finds the windows exactly where this
  /// one left them, without those in `closed`. Its recorded calls are kept, so a test can check
  /// that taking over moved nothing.
  func successor(
    saved: SavedState?, closing closed: [UInt32] = [], config: Config = Config()
  ) -> ManagerHarness {
    ManagerHarness(
      windows: backend.windows.filter { !closed.contains($0.id.rawValue) }, config: config,
      restoring: saved, clearRecordedCalls: false)
  }

  /// Where `spread` puts the window at `index`, before tylerd moves it.
  nonisolated static func originalFrame(index: Int) -> CGRect {
    CGRect(x: 100 + index * 50, y: 100, width: 300, height: 200)
  }

  func settle() async {
    await TylerServerTests.settle()
  }

  func frame(of windowID: UInt32) -> CGRect? {
    backend.frame(of: windowID)
  }

  func isParked(_ windowID: UInt32) -> Bool {
    guard let frame = frame(of: windowID) else { return false }
    return frame == Parking.frame(for: frame, on: display)
  }

  /// Whether macOS would accept every position tylerd asked for without pulling the window
  /// back on screen (see `Parking`).
  func everyPositionIsAllowed() -> Bool {
    let positions =
      backend.moves.map { ($0.id, $0.frame.origin) } + backend.nudges.map { ($0.id, $0.origin) }
    return positions.allSatisfy { windowID, origin in
      guard let width = frame(of: windowID.rawValue)?.width else { return false }
      return Parking.allowedX(width: width, on: display).contains(origin.x)
        && origin.y >= display.visibleFrame.minY
    }
  }

  /// Window id → 1-based workspace, for windows on a workspace.
  func workspaces() -> [UInt32: Int] {
    Dictionary(
      uniqueKeysWithValues: manager.listed.compactMap { window in
        window.workspace.map { (window.id.rawValue, $0) }
      })
  }

  /// Focuses `windowID` the way the OS would, and waits for the manager to see it.
  func osFocus(_ windowID: UInt32) async {
    backend.send(.focused(WindowID(windowID)))
    await settle()
  }
}

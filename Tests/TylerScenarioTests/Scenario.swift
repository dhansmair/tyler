import CoreGraphics
import Testing
import TylerClient
import TylerConfig
import TylerCore
import TylerProtocol
import TylerTestSupport

@testable import TylerServer

/// A running tylerd on fakes, set up as a context (displays, which windows each workspace holds,
/// the layout), given inputs in the words of `docs/`, and read back as what the user would see:
/// each workspace's list, the frames, which windows are parked. See `devdocs/testing-strategy.md`.
///
/// Each input runs until things are quiet: the events handled, and the clock advanced until no
/// animation, swipe or debounce waits on it.
@MainActor
struct Scenario {
  /// Where the fingers move in a swipe. Moving them left brings in the next workspace, as on a
  /// page.
  enum Fingers {
    case left
    case right
  }

  let harness: ManagerHarness
  let pointer = FakePointer()
  /// What the window server stacks where: the tiled windows, and whatever a test puts in front.
  let stacking = FakeStacking()
  let gapCursor = FakeGapCursor()
  let clock = TestClock()
  private let displays: FakeDisplays

  /// `workspaces` maps a workspace number to its windows, in list order; each starts focused on
  /// its first window. `showing` lists the workspaces on screen; by default each display shows
  /// its first. Numbers belong to displays as the config's defaults say (1 to 4 on display 1, 5
  /// to 8 on display 2). With `animates`, animations step frame by frame on `clock` instead of
  /// snapping, so a test can see the windows on their way.
  ///
  /// tylerd starts from these workspaces as after a restart: it takes them over from a hand-over
  /// state and finds each window where the previous tylerd left it, on its workspace's display,
  /// parked unless its workspace is on screen.
  init(
    displays: [DisplayInfo] = [FakeDisplays.main],
    workspaces: [Int: [UInt32]],
    showing: [Int] = [],
    layout: LayoutKind = .tall,
    config: Config = Config(),
    configFile: FakeConfigFile? = nil,
    gate: FakeGate = FakeGate(isTrusted: true),
    animates: Bool = false
  ) async {
    self.displays = FakeDisplays(displays: displays)
    // Displays of its own: a manager consumes its displays' changes, so the probe must not see
    // the ones a test sends.
    let probe = ManagerHarness(
      windows: [], displays: FakeDisplays(displays: displays), config: config)
    let arranged = probe.manager.rows.keys.compactMap { probe.manager.display(for: $0) }
    guard var saved = probe.manager.handOver(), var rows = saved.displays else {
      preconditionFailure("a running tylerd hands its workspaces over")
    }
    Self.place(workspaces, showing: showing, layout: layout, in: &rows)
    saved.displays = rows
    saved.seen = workspaces.values.flatMap { $0 }.map(WindowID.init)
    harness = ManagerHarness(
      windows: Self.windows(in: rows, on: arranged), displays: self.displays, gate: gate,
      animator: animates ? Animator(clock: clock) : .snap, config: config, configFile: configFile,
      pointer: pointer, stacking: stacking, gapCursor: gapCursor, clock: clock,
      restoring: saved)
    await runUntilQuiet()
  }

  /// tylerd starts for the first time with `windows` open, as `tyler start` finds them, and
  /// tiles them. Their frames are where `tyler stop` and `tiling off` put them back.
  init(
    openAtStart windows: [WindowInfo],
    displays: [DisplayInfo] = [FakeDisplays.main],
    config: Config = Config(),
    configFile: FakeConfigFile? = nil,
    gate: FakeGate = FakeGate(isTrusted: true),
    animates: Bool = false
  ) async {
    self.displays = FakeDisplays(displays: displays)
    harness = ManagerHarness(
      windows: windows, displays: self.displays, gate: gate,
      animator: animates ? Animator(clock: clock) : .snap, config: config, configFile: configFile,
      pointer: pointer, stacking: stacking, gapCursor: gapCursor, clock: clock)
    await runUntilQuiet()
  }

  /// The tylerd that `previous` hands over to on `tyler restart`, started with `config`. It finds
  /// the windows where `previous` left them, and keeps the calls `previous` recorded.
  private init(after previous: Scenario, config: Config) async {
    displays = FakeDisplays(displays: previous.displays.displays)
    harness = ManagerHarness(
      windows: previous.windowSystem.windows, displays: displays, config: config,
      pointer: pointer, stacking: stacking, gapCursor: gapCursor, clock: clock,
      restoring: previous.harness.manager.handOver(), clearRecordedCalls: false)
    await runUntilQuiet()
  }

  private static func place(
    _ workspaces: [Int: [UInt32]], showing: [Int], layout: LayoutKind,
    in rows: inout [SavedState.SavedDisplay]
  ) {
    for (number, windows) in workspaces {
      guard let display = rows.firstIndex(where: { $0.numbers.contains(number) }),
        let index = rows[display].numbers.firstIndex(of: number)
      else { preconditionFailure("no display has workspace \(number)") }
      let ids = windows.map(WindowID.init)
      rows[display].workspaces[index].windows = ids
      rows[display].workspaces[index].focused = ids.first
    }
    for display in rows.indices {
      for index in rows[display].workspaces.indices {
        rows[display].workspaces[index].layout = layout
      }
      if let shown = showing.compactMap({ rows[display].numbers.firstIndex(of: $0) }).first {
        rows[display].currentIndex = shown
      }
    }
  }

  /// The windows of `rows`, each on its display (`arranged`, in the same order), parked unless
  /// its workspace is on screen.
  private static func windows(
    in rows: [SavedState.SavedDisplay], on arranged: [DisplayInfo]
  ) -> [WindowInfo] {
    zip(rows, arranged).flatMap { row, display in
      row.workspaces.indices.flatMap { index in
        row.workspaces[index].windows.enumerated().map { position, windowID in
          let area = display.visibleFrame
          let frame = CGRect(
            x: area.minX + 50 + CGFloat(position) * 50, y: area.minY + 50, width: 300,
            height: 200)
          let isShown = index == row.currentIndex
          return makeWindow(
            id: windowID.rawValue,
            frame: isShown ? frame : Parking.frame(for: frame, on: display))
        }
      }
    }
  }

  // MARK: - Inputs

  /// Runs `tyler <command>` (as typed, without `tyler`) and returns tylerd's answer.
  @discardableResult
  func command(_ command: String) async -> Response {
    let words = command.split(separator: " ").map(String.init)
    guard let invocation = try? CommandLineParser.parse(words),
      case .send(let request) = invocation.action
    else {
      Issue.record("not a command for tylerd: \(command)")
      return .error("not a command")
    }
    let response = harness.manager.handle(request)
    await runUntilQuiet()
    return response
  }

  /// The user clicks into `window`, or macOS focuses it.
  func focus(_ window: UInt32) async {
    harness.windowSystem.send(.focused(WindowID(window)))
    await runUntilQuiet()
  }

  /// An app opens `window`.
  func open(_ window: WindowInfo) async {
    harness.windowSystem.windows.append(window)
    harness.windowSystem.send(.created(window))
    await runUntilQuiet()
  }

  /// `window` closes, by its app or its close button.
  func close(_ window: UInt32) async {
    harness.windowSystem.windows.removeAll { $0.id.rawValue == window }
    harness.windowSystem.send(.destroyed(WindowID(window)))
    await runUntilQuiet()
  }

  /// macOS reports `window` changed: minimized or back, full screen, moved, a dialog.
  func change(_ window: WindowInfo) async {
    if let index = harness.windowSystem.windows.firstIndex(where: { $0.id == window.id }) {
      harness.windowSystem.windows[index] = window
    }
    harness.windowSystem.send(.updated(window))
    await runUntilQuiet()
  }

  /// The user drags `window` by its title bar until the pointer is in the middle of `region` of
  /// display `number`, and lets go. The app moves the window along, keeping its size, as apps do.
  func drag(_ window: UInt32, to region: Region, display number: Int = 1) async {
    guard let frame = frame(of: window) else {
      Issue.record("no window \(window)")
      return
    }
    let target = rect(region, display: number)
    let start = CGPoint(x: frame.midX, y: frame.minY + 10)
    let end = CGPoint(x: target.midX, y: target.midY)
    let offset = CGVector(dx: end.x - start.x, dy: end.y - start.y)
    pointer.isPrimaryButtonDown = true
    await harness.windowSystem.userMoves(window, to: frame.offsetBy(dx: offset.dx, dy: offset.dy))
    pointer.drag(to: end)
    await runUntilQuiet()
    pointer.release(at: end)
    await runUntilQuiet()
  }

  /// The user moves the pointer to `point`, with no button down.
  func movePointer(to point: CGPoint) async {
    pointer.move(to: point)
    await runUntilQuiet()
  }

  /// The user moves the pointer to the gap at `point`, presses there, drags it by `offset` and
  /// lets go. Returns whether tylerd took the press; if not, it went to whatever is there.
  @discardableResult
  func dragGap(at point: CGPoint, by offset: CGVector) async -> Bool {
    await movePointer(to: point)
    guard pointer.beginGrab(.gap, at: point) else { return false }
    let end = CGPoint(x: point.x + offset.dx, y: point.y + offset.dy)
    pointer.moveGrab(to: end)
    await runUntilQuiet()
    pointer.endGrab(at: end)
    await runUntilQuiet()
    return true
  }

  /// A swipe on the trackpad across 0.18 of its width, the fingers lifted at rest: past halfway
  /// with the default `swipe-distance`.
  func swipe(_ fingers: Fingers) async {
    let offset = fingers == .left ? -0.18 : 0.18
    for update: SwipeUpdate in [.began, .moved(offset: offset), .ended(velocity: 0)] {
      pointer.swipe(update)
    }
    await runUntilQuiet()
  }

  /// The displays change to `connected` (one plugged in or unplugged, or the Mac waking), and
  /// tylerd waits for them to settle.
  func changeDisplays(to connected: [DisplayInfo]) async {
    displays.displays = connected
    displays.sendChange()
    await runUntilQuiet()
  }

  /// `tyler restart`: this tylerd hands its workspaces over, and the next one, with `config`,
  /// takes over. Read the next one's view from the scenario returned.
  func restart(config: Config = Config()) async -> Scenario {
    await Scenario(after: self, config: config)
  }

  /// Lets the manager handle what it was sent, and advances the clock until nothing waits on it.
  func runUntilQuiet() async {
    await harness.settle()
    for _ in 0..<1000 {
      guard clock.hasSleepers else { return }
      clock.advance(by: Animator.defaultFrameInterval)
      await harness.settle()
    }
    Issue.record("still busy after 1000 frames")
  }

  // MARK: - What the user sees

  func frame(of window: UInt32) -> CGRect? {
    harness.frame(of: window)
  }

  /// The windows of workspace `number`, in list order.
  func list(_ number: Int) -> [UInt32] {
    harness.manager.listed
      .filter { $0.workspace == number && $0.slot != nil }
      .sorted { ($0.slot ?? 0) < ($1.slot ?? 0) }
      .map(\.id.rawValue)
  }

  /// Window id → workspace number, for the windows on a workspace.
  var workspaces: [UInt32: Int] {
    harness.workspaces()
  }

  /// What tylerd asked macOS to do (moves, focus, closes), and the refusals a test sets up.
  var windowSystem: FakeWindowSystem {
    harness.windowSystem
  }

  /// The workspace each display shows, by display number.
  var shown: [Int] {
    harness.manager.rows.entries.map { $0.row.number(at: $0.row.currentIndex) }
  }

  /// The window tylerd last focused.
  var focused: UInt32? {
    harness.windowSystem.focusCalls.last?.rawValue
  }

  /// Whether `window` waits just past the parking edge of one of the displays.
  func isParked(_ window: UInt32) -> Bool {
    guard let frame = frame(of: window) else { return false }
    return harness.manager.rows.keys.contains { key in
      harness.manager.display(for: key).map { frame == Parking.frame(for: frame, on: $0) } == true
    }
  }

  /// `region` of display `number`'s visible frame (without the menu bar and the Dock), its edges
  /// rounded to whole points as the layouts round them. Worked out here, not by the layout under
  /// test.
  func rect(_ region: Region, display number: Int = 1) -> CGRect {
    let keys = harness.manager.rows.keys
    guard keys.indices.contains(number - 1),
      let area = harness.manager.display(for: keys[number - 1])?.visibleFrame
    else {
      Issue.record("no display \(number)")
      return .null
    }
    return region.rect(in: area)
  }
}

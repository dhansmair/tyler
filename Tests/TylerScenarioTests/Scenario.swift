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
  let harness: ManagerHarness
  let pointer = FakePointer()
  /// What the window server stacks where: the tiled windows, and whatever a test puts in front.
  let stacking = FakeStacking()
  let gapCursor = FakeGapCursor()
  /// The menu bar items: what tylerd last showed in them.
  let indicator = FakeIndicator()
  let clock = TestClock()
  /// How far the clock moves for each frame of an animation.
  let frameInterval: Duration
  private let displays: FakeDisplays
  private let gate: FakeGate

  /// `workspaces` maps a workspace number to its windows, in list order; each starts focused on
  /// its first window. `showing` lists the workspaces on screen; by default each display shows
  /// its first. Numbers belong to displays as the config's defaults say (1 to 4 on display 1, 5
  /// to 8 on display 2). With `animates`, animations step frame by frame on `clock` instead of
  /// snapping, so a test can see the windows on their way; a slide between workspaces takes
  /// `slide`.
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
    animates: Bool = false,
    slide: Duration = Animator.defaultDuration,
    frameInterval: Duration = Animator.defaultFrameInterval
  ) async {
    self.frameInterval = frameInterval
    self.gate = gate
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
      animator: animates
        ? Animator(duration: slide, frameInterval: frameInterval, clock: clock) : .snap,
      config: config, configFile: configFile,
      pointer: pointer, stacking: stacking, gapCursor: gapCursor, indicator: indicator,
      clock: clock,
      restoring: saved)
    await runUntilQuiet()
  }

  /// tylerd starts for the first time with `windows` open, as `tyler start` finds them, and
  /// tiles them. Their frames are where `tyler stop` and `tiling off` put them back. What tylerd
  /// asked of the window system to tile them stays recorded in `windowSystem`.
  init(
    openAtStart windows: [WindowInfo],
    displays: [DisplayInfo] = [FakeDisplays.main],
    config: Config = Config(),
    configFile: FakeConfigFile? = nil,
    gate: FakeGate = FakeGate(isTrusted: true),
    animates: Bool = false,
    slide: Duration = Animator.defaultDuration,
    frameInterval: Duration = Animator.defaultFrameInterval
  ) async {
    self.frameInterval = frameInterval
    self.gate = gate
    self.displays = FakeDisplays(displays: displays)
    harness = ManagerHarness(
      windows: windows, displays: self.displays, gate: gate,
      animator: animates
        ? Animator(duration: slide, frameInterval: frameInterval, clock: clock) : .snap,
      config: config, configFile: configFile,
      pointer: pointer, stacking: stacking, gapCursor: gapCursor, indicator: indicator,
      clock: clock,
      clearRecordedCalls: false)
    await runUntilQuiet()
  }

  /// The tylerd that `previous` hands over to on `tyler restart`, started with `config`. It finds
  /// the windows where `previous` left them, and keeps the calls `previous` recorded.
  private init(after previous: Scenario, config: Config) async {
    frameInterval = previous.frameInterval
    gate = previous.gate
    displays = FakeDisplays(displays: previous.displays.displays)
    harness = ManagerHarness(
      windows: previous.windowSystem.windows, displays: displays, config: config,
      pointer: pointer, stacking: stacking, gapCursor: gapCursor, indicator: indicator,
      clock: clock,
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
    let response = await start(command)
    await runUntilQuiet()
    return response
  }

  /// Gives `tyler <command>` and returns tylerd's answer before the first frame of what it
  /// starts, so a test can follow an animation with `wait(_:)`.
  @discardableResult
  func start(_ command: String) async -> Response {
    let words = command.split(separator: " ").map(String.init)
    guard let invocation = try? CommandLineParser.parse(words),
      case .send(let request) = invocation.action
    else {
      Issue.record("not a command for tylerd: \(command)")
      return .error("not a command")
    }
    let response = harness.manager.handle(request)
    await harness.settle()
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

  /// Lets `time` pass in one go, as when moving the windows took that long, and lets tylerd
  /// handle what is due.
  func wait(_ time: Duration) async {
    clock.advance(by: time)
    await harness.settle()
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

  /// The user grants Accessibility permission, and tylerd, which was waiting for it, starts.
  func grantPermission() async {
    gate.isTrusted = true
    harness.manager.startIfPermitted()
    await runUntilQuiet()
  }

  /// Lets the manager handle what it was sent, and advances the clock until nothing waits on it.
  func runUntilQuiet() async {
    await harness.settle()
    for _ in 0..<1000 {
      guard clock.hasSleepers else { return }
      clock.advance(by: frameInterval)
      await harness.settle()
    }
    Issue.record("still busy after 1000 frames")
  }
}

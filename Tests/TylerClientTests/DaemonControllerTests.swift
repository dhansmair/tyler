import Foundation
import Testing
import TylerCore

@testable import TylerClient

/// A pretend operating system: one server process that the controller can start and stop, a
/// clock that only moves on `pause`, and a few files.
final class FakeDaemonSystem: DaemonSystem {
  enum Server {
    case none
    case running(ServerStatus)
    /// Answers every request with an error, like a server built before `status` existed.
    case outdated
    /// Accepts connections but never replies.
    case hung
  }

  /// What a spawned server does.
  enum SpawnBehaviour {
    /// Answers `status` after this many pauses.
    case answersAfter(pauses: Int)
    case exitsAtOnce(log: String)
    case neverAnswers
    case fails(String)
  }

  /// What the running server does on SIGTERM.
  enum StopBehaviour {
    case exitsAfter(pauses: Int)
    case ignoresIt
    case cannotBeSignalled
  }

  static let serverPath = "/build/tylerd"
  static let logPath = "/home/.tyler/tyler.log"
  static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  var server: Server = .none
  var spawnBehaviour: SpawnBehaviour = .answersAfter(pauses: 2)
  var stopBehaviour: StopBehaviour = .exitsAfter(pauses: 2)
  var executables: Set<String> = [serverPath]
  var modificationDates: [String: Date] = [serverPath: start]
  var nextPID: Int32 = 200
  private(set) var now = start
  private(set) var spawned: [(executable: String, logPath: String)] = []
  private(set) var terminated: [Int32] = []
  private(set) var pauses = 0

  private var pendingStart: (pid: Int32, readyAt: Int)?
  private var exitedChild: Int32?
  private var stopping: (pid: Int32, goneAt: Int)?

  static func status(pid: Int32, startedAt: Date = start) -> ServerStatus {
    ServerStatus(
      pid: pid, executablePath: serverPath, executableModified: start, startedAt: startedAt,
      configPath: "/home/.config/tyler/tyler.toml", tiling: .on)
  }

  func send(_ request: Request) throws -> Response {
    switch server {
    case .none: throw IPCClientError.serverNotRunning("/home/.tyler/tyler.sock")
    case .running(let status): return .status(status)
    case .outdated: return .error("malformed request")
    case .hung: throw IPCClientError.badReply
    }
  }

  func spawn(_ executable: String, logPath: String) throws(DaemonError) -> Int32 {
    if case .fails(let reason) = spawnBehaviour { throw .spawnFailed(reason) }
    spawned.append((executable, logPath))
    let pid = nextPID
    nextPID += 1
    switch spawnBehaviour {
    case .answersAfter(let count): pendingStart = (pid, pauses + count)
    case .exitsAtOnce: exitedChild = pid
    case .neverAnswers, .fails: break
    }
    return pid
  }

  func terminate(_ pid: Int32) -> Bool {
    if case .cannotBeSignalled = stopBehaviour { return false }
    terminated.append(pid)
    if case .exitsAfter(let count) = stopBehaviour { stopping = (pid, pauses + count) }
    return true
  }

  func childHasExited(_ pid: Int32) -> Bool { exitedChild == pid }

  func isRunning(_ pid: Int32) -> Bool {
    guard case .running(let status) = server else { return false }
    return status.pid == pid
  }

  func isExecutable(atPath path: String) -> Bool { executables.contains(path) }

  func modificationDate(ofFile path: String) -> Date? { modificationDates[path] }

  func lastLines(ofFile path: String, count: Int) -> String {
    guard path == Self.logPath, case .exitsAtOnce(let log) = spawnBehaviour else { return "" }
    return log
  }

  func pause(_ duration: Duration) {
    pauses += 1
    now += Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    if let (pid, readyAt) = pendingStart, pauses >= readyAt {
      server = .running(Self.status(pid: pid, startedAt: now))
      pendingStart = nil
    }
    if let (_, goneAt) = stopping, pauses >= goneAt {
      server = .none
      stopping = nil
    }
  }
}

@Suite("DaemonController")
struct DaemonControllerTests {
  private func makeController(_ system: FakeDaemonSystem) -> DaemonController {
    DaemonController(
      system: system, serverPath: FakeDaemonSystem.serverPath, logPath: FakeDaemonSystem.logPath)
  }

  private let outdatedMessage =
    "a tylerd from an older build is running, and it can't be stopped from here; stop it with "
    + "`pkill tylerd` (or Ctrl-C in its terminal), then run `tyler start`"

  // MARK: - start

  @Test func startLaunchesTheServerAndWaitsForItToAnswer() {
    let system = FakeDaemonSystem()
    let response = makeController(system).run(.start)

    #expect(response == .message("started tylerd (pid 200), output in /home/.tyler/tyler.log"))
    #expect(system.spawned.map(\.executable) == [FakeDaemonSystem.serverPath])
    #expect(system.spawned.map(\.logPath) == [FakeDaemonSystem.logPath])
    #expect(system.pauses == 2)
  }

  @Test func startDoesNothingWhenTheServerIsAlreadyRunning() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77))

    #expect(makeController(system).run(.start) == .message("tylerd is already running (pid 77)"))
    #expect(system.spawned.isEmpty)
  }

  @Test func startWarnsWhenTheRunningServerIsStale() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77))
    system.modificationDates[FakeDaemonSystem.serverPath] = FakeDaemonSystem.start + 60

    #expect(
      makeController(system).run(.start)
        == .message(
          "tylerd is already running (pid 77)\nwarning: tylerd has been rebuilt since it started; "
            + "run `tyler restart` to use the new build"))
  }

  @Test func startRefusesWhenAnOutdatedServerHoldsTheSocket() {
    let system = FakeDaemonSystem()
    system.server = .outdated

    #expect(makeController(system).run(.start) == .error(outdatedMessage))
    #expect(system.spawned.isEmpty)
  }

  @Test func startNeedsTheServerBinary() {
    let system = FakeDaemonSystem()
    system.executables = []

    #expect(
      makeController(system).run(.start)
        == .error("cannot find tylerd at /build/tylerd (tyler starts the tylerd in its own folder)")
    )
  }

  @Test func startReportsASpawnFailure() {
    let system = FakeDaemonSystem()
    system.spawnBehaviour = .fails("Permission denied")

    #expect(makeController(system).run(.start) == .error("cannot start tylerd: Permission denied"))
  }

  @Test func startShowsTheLogWhenTheServerExitsAtOnce() {
    let system = FakeDaemonSystem()
    system.spawnBehaviour = .exitsAtOnce(log: "tylerd: already running (socket /x.sock)")

    #expect(
      makeController(system).run(.start)
        == .error("tylerd exited right after starting:\ntylerd: already running (socket /x.sock)"))
  }

  @Test func startGivesUpWhenTheServerNeverAnswers() {
    let system = FakeDaemonSystem()
    system.spawnBehaviour = .neverAnswers

    #expect(
      makeController(system).run(.start)
        == .error("tylerd (pid 200) started but did not answer; see /home/.tyler/tyler.log"))
    #expect(system.pauses == 100, "10 s in steps of 100 ms")
  }

  // MARK: - stop

  @Test func stopSendsSIGTERMAndWaitsForTheProcessToEnd() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77))

    #expect(makeController(system).run(.stop) == .message("stopped tylerd (pid 77)"))
    #expect(system.terminated == [77])
    #expect(system.pauses == 2)
  }

  @Test func stopWhenNothingRunsIsNotAnError() {
    let system = FakeDaemonSystem()
    #expect(makeController(system).run(.stop) == .message("tylerd is not running"))
    #expect(system.terminated.isEmpty)
  }

  @Test func stopCannotStopAnOutdatedServer() {
    let system = FakeDaemonSystem()
    system.server = .outdated
    #expect(makeController(system).run(.stop) == .error(outdatedMessage))
  }

  @Test func stopReportsAServerThatDoesNotAnswer() {
    let system = FakeDaemonSystem()
    system.server = .hung
    #expect(makeController(system).run(.stop) == .error("tylerd is running but did not answer"))
  }

  @Test func stopReportsWhenTheSignalCannotBeSent() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77))
    system.stopBehaviour = .cannotBeSignalled
    #expect(makeController(system).run(.stop) == .error("cannot send SIGTERM to tylerd (pid 77)"))
  }

  @Test func stopGivesUpOnAServerThatKeepsRunning() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77))
    system.stopBehaviour = .ignoresIt

    let response = makeController(system).run(.stop)
    #expect(
      response
        == .error(
          "tylerd (pid 77) is still running; it may be stuck putting windows back "
            + "(`kill -9 77` stops it, but leaves parked windows in the corner)"))
    #expect(system.pauses == 100)
  }

  // MARK: - restart

  @Test func restartStopsAndStartsTheServer() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77))

    #expect(
      makeController(system).run(.restart)
        == .message("restarted tylerd (pid 77 → 200), output in /home/.tyler/tyler.log"))
    #expect(system.terminated == [77])
    #expect(system.spawned.count == 1)
  }

  @Test func restartStartsTheServerWhenNothingRuns() {
    let system = FakeDaemonSystem()
    #expect(
      makeController(system).run(.restart)
        == .message(
          "tylerd was not running; started it (pid 200), output in /home/.tyler/tyler.log"))
  }

  @Test func restartDoesNotStartWhenStoppingFails() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77))
    system.stopBehaviour = .cannotBeSignalled

    #expect(
      makeController(system).run(.restart) == .error("cannot send SIGTERM to tylerd (pid 77)"))
    #expect(system.spawned.isEmpty)
  }

  // MARK: - status

  @Test func statusDescribesTheRunningServer() {
    let system = FakeDaemonSystem()
    system.server = .running(
      FakeDaemonSystem.status(pid: 77, startedAt: FakeDaemonSystem.start - 3_725))

    #expect(
      makeController(system).run(.status)
        == .message(
          """
          tylerd is running (pid 77, up 1h 2m)
            binary  /build/tylerd
            config  /home/.config/tyler/tyler.toml
            tiling  on
          """))
  }

  @Test func statusWarnsAboutAStaleServer() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77))
    system.modificationDates[FakeDaemonSystem.serverPath] = FakeDaemonSystem.start + 1

    guard case .message(let text) = makeController(system).run(.status) else {
      Issue.record("expected a message")
      return
    }
    #expect(
      text.hasSuffix(
        "\nwarning: tylerd has been rebuilt since it started; run `tyler restart` to use the new build"
      ))
  }

  @Test func statusWhenNothingRunsIsAnError() {
    #expect(makeController(FakeDaemonSystem()).run(.status) == .error("tylerd is not running"))
  }

  @Test func statusNamesAnOutdatedServer() {
    let system = FakeDaemonSystem()
    system.server = .outdated
    #expect(makeController(system).run(.status) == .error(outdatedMessage))
  }

  @Test(arguments: [
    (0.0, "0s"), (59, "59s"), (60, "1m"), (3_599, "59m"), (3_600, "1h 0m"), (3_725, "1h 2m"),
    (86_400, "1d 0h"), (90_000, "1d 1h"), (-5, "0s"),
  ])
  func describesUptime(seconds: TimeInterval, expected: String) {
    #expect(DaemonController.describe(uptime: seconds) == expected)
  }

  @Test func theServerIsLookedForNextToTheClient() {
    let client = URL(fileURLWithPath: "/opt/tyler/bin/tyler")
    #expect(DaemonController.serverPath(nextTo: client) == "/opt/tyler/bin/tylerd")
  }
}

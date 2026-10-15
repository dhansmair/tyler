import Foundation
import Testing
import TylerProtocol
import TylerRuntime

@testable import TylerClient

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
    #expect(system.handedOver.isEmpty, "stop always puts the windows back")
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
    #expect(makeController(system).run(.stop) == .error("cannot signal tylerd (pid 77)"))
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
            + "(`kill -9 77` stops it, but leaves parked windows at the right edge)"))
    #expect(system.pauses == 100)
  }

  // MARK: - restart

  @Test func restartAsksTheServerToHandOverSoTheWindowsStay() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77))

    #expect(
      makeController(system).run(.restart)
        == .message("restarted tylerd (pid 77 → 200), output in /home/.tyler/tyler.log"))
    #expect(system.handedOver == [77])
    #expect(system.terminated.isEmpty)
    #expect(system.spawned.count == 1)
  }

  @Test func restartStopsAServerTooOldToHandOver() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77, keepsWindows: nil))

    #expect(
      makeController(system).run(.restart)
        == .message(
          "restarted tylerd (pid 77 → 200), output in /home/.tyler/tyler.log\n"
            + "(the old tylerd could not hand over, so its windows went back where they were)"))
    #expect(system.terminated == [77])
    #expect(system.handedOver.isEmpty)
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
      makeController(system).run(.restart) == .error("cannot signal tylerd (pid 77)"))
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
            version \(TylerVersion.current)
            binary  /build/tylerd
            config  /home/.config/tyler/tyler.toml
            tiling  on
            access  sees the windows
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

  @Test(arguments: [("0.0.9", "0.0.9"), (nil, "older than 0.1.0")])
  func statusWarnsAboutAnotherVersion(version: String?, shown: String) {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77, version: version))
    guard case .message(let text) = makeController(system).run(.status) else {
      Issue.record("expected a message")
      return
    }
    #expect(text.contains("\n  version \(shown)\n"))
    #expect(
      text.hasSuffix(
        "\nwarning: tylerd is version \(shown), this tyler is \(TylerVersion.current); "
          + "run `tyler restart`"))
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

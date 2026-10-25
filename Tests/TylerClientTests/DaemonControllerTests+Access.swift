import Testing
import TylerCore
import TylerProtocol

@testable import TylerClient

/// `tyler start`, `restart` and `status` say when tylerd can't reach the windows, with the fix,
/// and leave it running: it starts by itself once the permission works.
@Suite("DaemonController: access to the windows")
struct DaemonControllerAccessTests {
  private let started = "started tylerd (pid 200), output in /home/.tyler/tyler.log"

  private func run(
    _ command: DaemonCommand, reports: [WindowAccess?], running: Bool = false
  ) -> (Response, FakeDaemonSystem) {
    let system = FakeDaemonSystem()
    system.accessReports = reports
    if running { system.server = .running(FakeDaemonSystem.status(pid: 77)) }
    let controller = DaemonController(
      system: system, serverPath: FakeDaemonSystem.serverPath, logPath: FakeDaemonSystem.logPath)
    return (controller.run(command), system)
  }

  @Test(arguments: [WindowAccess.notTrusted, .refused, .blind])
  func startFailsWithTheFixWhenTylerdCanNotReachTheWindows(access: WindowAccess) throws {
    let (response, system) = run(.start, reports: [access])
    let problem = try #require(access.problem(app: nil))
    #expect(response == .error(started + "\n" + problem))
    #expect(system.terminated.isEmpty, "tylerd keeps running")
  }

  @Test(arguments: [nil, WindowAccess.ok])
  func startSaysNothingMoreWhenAllIsWell(access: WindowAccess?) {
    #expect(run(.start, reports: [access]).0 == .message(started))
  }

  @Test func startWaitsForAppsThatHaveNotAnsweredYet() {
    let (response, system) = run(.start, reports: [.checking, .checking, .blind])
    #expect(response == .error(started + "\n" + (WindowAccess.blind.problem(app: nil) ?? "")))
    #expect(system.pauses == 4, "2 until tylerd answers, 2 until the apps have")
  }

  @Test func startStopsWaitingForAppsAfterAWhile() {
    let (response, system) = run(.start, reports: [.checking])
    #expect(response == .message(started + "\nnote: " + (WindowAccess.checking.note ?? "")))
    #expect(system.pauses == 2 + 40, "4 s in steps of 100 ms")
  }

  @Test func startNotesALockedScreen() {
    #expect(
      run(.start, reports: [.screenLocked]).0
        == .message(
          started + "\nnote: the screen is locked; tylerd tracks windows once it is unlocked"))
  }

  @Test func startOnARunningTylerdChecksItsAccessToo() {
    let (response, _) = run(.start, reports: [.refused], running: true)
    #expect(
      response
        == .error(
          "tylerd is already running (pid 77)\n" + (WindowAccess.refused.problem(app: nil) ?? "")))
  }

  @Test func restartChecksTheNewTylerd() {
    guard case .error(let text) = run(.restart, reports: [.ok, .notTrusted], running: true).0 else {
      Issue.record("restart reported no error")
      return
    }
    #expect(text.hasPrefix("restarted tylerd (pid 77 → 200)"))
    #expect(text.hasSuffix(WindowAccess.notTrusted.problem(app: nil) ?? ""))
  }

  @Test func statusShowsTheAccessAndWhatToFix() {
    guard case .message(let text) = run(.status, reports: [.blind], running: true).0 else {
      Issue.record("status reported an error")
      return
    }
    #expect(
      text.contains(
        "  tiling  on\n  access  sees none of the windows on screen\nwarning: tylerd sees none"))
  }

  @Test func statusOfAnOlderTylerdLeavesTheAccessOut() {
    guard case .message(let text) = run(.status, reports: [nil], running: true).0 else {
      Issue.record("status reported an error")
      return
    }
    #expect(!text.contains("access"))
  }
}

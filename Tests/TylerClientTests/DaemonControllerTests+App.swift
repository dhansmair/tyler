import Testing
import TylerCore
import TylerProtocol

@testable import TylerClient

/// `tyler start` launches the `Tyler.app` next to `tyler` when there is one, so tylerd holds its
/// own Accessibility grant, and the bare `tylerd` otherwise.
@Suite("DaemonController: the app")
struct DaemonControllerAppTests {
  private let app = AppLaunch(
    path: FakeDaemonSystem.appPath, installedPath: FakeDaemonSystem.installedAppPath,
    environment: ["TYLER_SOCKET": "/home/.tyler/tyler.sock"])

  private func controller(_ system: FakeDaemonSystem, hasApp: Bool = true) -> DaemonController {
    if hasApp { system.executables.insert(app.executablePath) }
    return DaemonController(
      system: system, serverPath: FakeDaemonSystem.serverPath, logPath: FakeDaemonSystem.logPath,
      app: app)
  }

  @Test func startLaunchesTheApp() {
    let system = FakeDaemonSystem()
    let response = controller(system).run(.start)
    #expect(response == .message("started tylerd (pid 200), output in /home/.tyler/tyler.log"))
    #expect(system.launchedApps.map(\.path) == [FakeDaemonSystem.appPath])
    #expect(system.launchedApps.map(\.environment) == [app.environment])
    #expect(system.spawned.isEmpty)
  }

  @Test func startRunsTheBareTylerdWithoutTheApp() {
    let system = FakeDaemonSystem()
    _ = controller(system, hasApp: false).run(.start)
    #expect(system.launchedApps.isEmpty)
    #expect(system.spawned.map(\.executable) == [FakeDaemonSystem.serverPath])
  }

  @Test func restartLaunchesTheAppAfterTheHandOver() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77, executablePath: app.executablePath))
    let response = controller(system).run(.restart)
    #expect(
      response
        == .message("restarted tylerd (pid 77 → 200), output in /home/.tyler/tyler.log"))
    #expect(system.handedOver == [77])
    #expect(system.launchedApps.count == 1)
  }

  @Test func anAppOlderThanTheTylerdNextToItIsRefused() {
    let system = FakeDaemonSystem()
    system.modificationDates[app.executablePath] = FakeDaemonSystem.start.addingTimeInterval(-60)
    #expect(
      controller(system).run(.start)
        == .error(DaemonError.staleApp(FakeDaemonSystem.appPath).description))
    #expect(system.launchedApps.isEmpty)
    #expect(system.spawned.isEmpty)
  }

  /// The app holds a grant of its own, maybe none yet: until it has one, it couldn't take on the
  /// parked windows of a tylerd that ran under the terminal's.
  /// The workspaces are handed over all the same, and come back once the app has its grant.
  @Test func restartFromTheBareTylerdToTheAppPutsTheWindowsBack() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77))
    let response = controller(system).run(.restart)
    #expect(system.handedOverPuttingWindowsBack == [77])
    #expect(system.handedOver.isEmpty)
    #expect(system.terminated.isEmpty)
    #expect(system.launchedApps.count == 1)
    #expect(
      response
        == .message(
          "restarted tylerd (pid 77 → 200), output in /home/.tyler/tyler.log\n(the new tylerd "
            + "runs from elsewhere, with a permission of its own, so the old one put its windows "
            + "back where they were; they go back to their workspaces once it has the "
            + "permission)"))
  }

  @Test func restartFromTheAppToTheBareTylerdPutsTheWindowsBack() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77, executablePath: app.executablePath))
    _ = controller(system, hasApp: false).run(.restart)
    #expect(system.handedOverPuttingWindowsBack == [77])
    #expect(system.spawned.count == 1)
  }

  /// A tylerd from before SIGUSR2 would die on it without cleaning up, leaving windows parked.
  @Test func aTylerdTooOldToPutWindowsBackOnAHandOverIsStopped() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77, putsWindowsBack: nil))
    let response = controller(system).run(.restart)
    #expect(system.terminated == [77])
    #expect(system.handedOverPuttingWindowsBack.isEmpty)
    #expect(
      response
        == .message(
          "restarted tylerd (pid 77 → 200), output in /home/.tyler/tyler.log\n(the new tylerd "
            + "runs from elsewhere, with a permission of its own, so the old one put its windows "
            + "back where they were)"))
  }

  @Test func statusWarnsWhenTheRunningAppIsOlderThanTheTylerdNextToIt() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77, executablePath: app.executablePath))
    system.modificationDates[app.executablePath] = FakeDaemonSystem.start.addingTimeInterval(-60)
    guard case .message(let text) = controller(system).run(.status) else {
      Issue.record("status reported an error")
      return
    }
    #expect(text.contains("warning: /build/Tyler.app is older than the tylerd next to it"))
  }

  /// Stopping first would leave the old tylerd's windows parked with no tylerd to take them on.
  @Test func restartRefusesAStaleAppBeforeStopping() {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77))
    system.modificationDates[app.executablePath] = FakeDaemonSystem.start.addingTimeInterval(-60)
    #expect(
      controller(system).run(.restart)
        == .error(DaemonError.staleApp(FakeDaemonSystem.appPath).description))
    #expect(system.handedOver.isEmpty)
    #expect(system.isRunning(77))
  }

  @Test func anAppAsNewAsTheTylerdNextToItIsLaunched() {
    let system = FakeDaemonSystem()
    system.modificationDates[app.executablePath] = FakeDaemonSystem.start
    _ = controller(system).run(.start)
    #expect(system.launchedApps.count == 1)
  }

  @Test func aFailingLaunchIsAnError() {
    let system = FakeDaemonSystem()
    system.launchFailure = "open /build/Tyler.app failed: no such app"
    #expect(
      controller(system).run(.start)
        == .error("cannot start tylerd: open /build/Tyler.app failed: no such app"))
  }

  @Test func anAppThatNeverAnswersHasNoPidToName() {
    let system = FakeDaemonSystem()
    system.spawnBehaviour = .neverAnswers
    #expect(
      controller(system).run(.start)
        == .error("tylerd started but did not answer; see /home/.tyler/tyler.log"))
  }

  @Test func theAdviceNamesTheApp() {
    let system = FakeDaemonSystem()
    system.server = .running(
      FakeDaemonSystem.status(pid: 77, access: .notTrusted, appName: "Tyler.app"))
    guard case .message(let text) = controller(system).run(.status) else {
      Issue.record("status reported an error")
      return
    }
    #expect(text.contains("Turn on Tyler.app under System Settings"))
    #expect(!text.contains("terminal"))
  }
}

import Foundation
import Testing
import TylerCore
import TylerProtocol

@testable import TylerClient

/// A release `Tyler.app` runs from its copy in `~/Applications`, where Spotlight finds it:
/// `tyler start` and `restart` install the build next to `tyler` there when it isn't yet.
@Suite("DaemonController: the app in ~/Applications")
struct DaemonControllerInstalledAppTests {
  private let app = AppLaunch(
    path: FakeDaemonSystem.appPath, installedPath: FakeDaemonSystem.installedAppPath,
    environment: [:])
  private let installedExecutable = FakeDaemonSystem.installedAppPath + "/Contents/MacOS/tylerd"
  private let installedNote =
    "\n(copied the new build of Tyler.app to /home/Applications/Tyler.app)"

  private func system(installedBuild: String? = nil) -> FakeDaemonSystem {
    let system = FakeDaemonSystem()
    system.executables.insert(app.executablePath)
    system.appInfos[FakeDaemonSystem.appPath] = AppInfo(
      build: "2", installsInApplications: true)
    if let installedBuild {
      system.appInfos[FakeDaemonSystem.installedAppPath] = AppInfo(
        build: installedBuild, installsInApplications: true)
      system.executables.insert(installedExecutable)
    }
    return system
  }

  private func controller(_ system: FakeDaemonSystem) -> DaemonController {
    DaemonController(
      system: system, serverPath: FakeDaemonSystem.serverPath, logPath: FakeDaemonSystem.logPath,
      app: app)
  }

  @Test func startInstallsTheAppAndLaunchesTheCopy() {
    let system = system()
    let response = controller(system).run(.start)
    #expect(system.replaced.map(\.destination) == [FakeDaemonSystem.installedAppPath])
    #expect(system.launchedApps.map(\.path) == [FakeDaemonSystem.installedAppPath])
    #expect(
      response
        == .message(
          "started tylerd (pid 200), output in /home/.tyler/tyler.log" + installedNote))
  }

  @Test func startLaunchesTheCopyAsItIsWhenItIsThisBuild() {
    let system = system(installedBuild: "2")
    let response = controller(system).run(.start)
    #expect(system.replaced.isEmpty)
    #expect(system.launchedApps.map(\.path) == [FakeDaemonSystem.installedAppPath])
    #expect(response == .message("started tylerd (pid 200), output in /home/.tyler/tyler.log"))
  }

  @Test func startReplacesACopyOfAnotherBuild() {
    let system = system(installedBuild: "1")
    _ = controller(system).run(.start)
    #expect(system.replaced.map(\.destination) == [FakeDaemonSystem.installedAppPath])
  }

  /// The copy runs from the same place before and after, so the old tylerd hands over; the new
  /// build is staged before the stop and put in place only once the old tylerd has quit.
  @Test func restartOntoANewBuildHandsOverAndReplacesTheCopyAfterTheStop() {
    let system = system(installedBuild: "1")
    system.server = .running(FakeDaemonSystem.status(pid: 77, executablePath: installedExecutable))
    let response = controller(system).run(.restart)
    #expect(system.handedOver == [77])
    #expect(system.staged.count == 1)
    #expect(system.replaced.map(\.whileRunning) == [false])
    #expect(
      response
        == .message(
          "restarted tylerd (pid 77 → 200), output in /home/.tyler/tyler.log" + installedNote))
  }

  /// The old tylerd would hand over to nobody, leaving windows parked.
  @Test func restartWhoseCopyFailsStopsNothing() {
    let system = system(installedBuild: "1")
    system.server = .running(FakeDaemonSystem.status(pid: 77, executablePath: installedExecutable))
    system.stageFailure = "disk full"
    #expect(
      controller(system).run(.restart)
        == .error("cannot install tylerd's app at /home/Applications/Tyler.app: disk full"))
    #expect(system.handedOver.isEmpty)
    #expect(system.isRunning(77))
  }

  /// After the hand-over the old copy is still there, and takes on the parked windows.
  @Test func restartWhoseSwapFailsLaunchesTheOldCopy() {
    let system = system(installedBuild: "1")
    system.server = .running(FakeDaemonSystem.status(pid: 77, executablePath: installedExecutable))
    system.replaceFailure = "busy"
    let response = controller(system).run(.restart)
    #expect(system.handedOver == [77])
    #expect(system.launchedApps.map(\.path) == [FakeDaemonSystem.installedAppPath])
    #expect(
      response
        == .message(
          "restarted tylerd (pid 77 → 200), output in /home/.tyler/tyler.log\n(the new build of "
            + "Tyler.app couldn't be put in place, so the one at /home/Applications/Tyler.app "
            + "runs: cannot install tylerd's app at /home/Applications/Tyler.app: busy)"))
  }

  @Test func aFirstInstallWhoseSwapFailsIsAnError() {
    let system = system()
    system.replaceFailure = "busy"
    #expect(
      controller(system).run(.start)
        == .error("cannot install tylerd's app at /home/Applications/Tyler.app: busy"))
    #expect(system.launchedApps.isEmpty)
  }

  @Test func statusWarnsWhenANewBuildIsNextToTyler() {
    let system = system(installedBuild: "1")
    system.server = .running(FakeDaemonSystem.status(pid: 77, executablePath: installedExecutable))
    guard case .message(let text) = controller(system).run(.status) else {
      Issue.record("status reported an error")
      return
    }
    #expect(
      text.contains("warning: a new build of Tyler.app is next to tyler; run `tyler restart`"))
  }

  @Test func aDevelopmentBuildRunsWhereItWasBuilt() {
    let system = system()
    system.appInfos[FakeDaemonSystem.appPath] = AppInfo(build: "2", installsInApplications: false)
    _ = controller(system).run(.start)
    #expect(system.replaced.isEmpty)
    #expect(system.launchedApps.map(\.path) == [FakeDaemonSystem.appPath])
  }
}

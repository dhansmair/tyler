import Testing
import TylerCore
import TylerProtocol

@testable import TylerClient

/// A release signed ad hoc is another identity to macOS with every build: its entry stays switched
/// on but no longer works (measured). `restart` onto a new build puts the windows back, hands the
/// workspaces over, and resets the entry once the old tylerd has quit, so macOS asks again.
@Suite("DaemonController: an app signed ad hoc")
struct DaemonControllerAdHocAppTests {
  private let bundleID = "io.github.dhansmair.tyler"
  private let app = AppLaunch(
    path: FakeDaemonSystem.appPath, installedPath: FakeDaemonSystem.installedAppPath,
    environment: [:])
  private let installedExecutable = FakeDaemonSystem.installedAppPath + "/Contents/MacOS/tylerd"
  private let installedNote =
    "\n(copied the new build of Tyler.app to /home/Applications/Tyler.app)"

  /// Build `running` of the app runs from `~/Applications`; build `new` is next to `tyler`.
  private func system(running: String, new: String, adHoc: Bool = true) -> FakeDaemonSystem {
    let system = FakeDaemonSystem()
    system.executables.formUnion([app.executablePath, installedExecutable])
    system.appInfos[FakeDaemonSystem.appPath] = AppInfo(
      build: new, installsInApplications: true, bundleID: bundleID, isSignedAdHoc: adHoc)
    system.appInfos[FakeDaemonSystem.installedAppPath] = AppInfo(
      build: running, installsInApplications: true, bundleID: bundleID, isSignedAdHoc: adHoc)
    system.server = .running(
      FakeDaemonSystem.status(
        pid: 77, executablePath: installedExecutable, appName: "Tyler.app",
        appBundleID: bundleID, appBuild: running))
    return system
  }

  private func restart(_ system: FakeDaemonSystem) -> Response {
    DaemonController(
      system: system, serverPath: FakeDaemonSystem.serverPath, logPath: FakeDaemonSystem.logPath,
      app: app
    ).run(.restart)
  }

  @Test func aNewBuildPutsTheWindowsBackAndResetsTheEntryOnceTheOldTylerdHasQuit() {
    let system = system(running: "1", new: "2")
    let response = restart(system)
    #expect(system.handedOverPuttingWindowsBack == [77])
    #expect(system.resets.map(\.bundleID) == [bundleID])
    #expect(system.resets.map(\.whileRunning) == [false])
    #expect(system.launchedApps.map(\.path) == [FakeDaemonSystem.installedAppPath])
    #expect(
      response
        == .message(
          "restarted tylerd (pid 77 → 200), output in /home/.tyler/tyler.log" + installedNote
            + "\n(the new build is signed ad hoc, which macOS treats as another app that needs the "
            + "permission again, so the old one put its windows back where they were; they go "
            + "back to their workspaces once the new one has the permission)"))
  }

  @Test func theSameBuildHandsOverAndKeepsTheEntry() {
    let system = system(running: "2", new: "2")
    _ = restart(system)
    #expect(system.handedOver == [77])
    #expect(system.resets.isEmpty)
  }

  /// A certificate's signature stays the same identity across builds, and keeps its grant.
  @Test func aNewBuildSignedWithACertificateHandsOver() {
    let system = system(running: "1", new: "2", adHoc: false)
    _ = restart(system)
    #expect(system.handedOver == [77])
    #expect(system.resets.isEmpty)
  }

  /// Its bundle ID may have an entry from an earlier build, which can't work for this one.
  @Test func movingOntoAnAdHocAppFromElsewhereResetsItsEntryToo() {
    let system = system(running: "1", new: "2")
    system.server = .running(FakeDaemonSystem.status(pid: 77))
    _ = restart(system)
    #expect(system.handedOverPuttingWindowsBack == [77])
    #expect(system.resets.map(\.bundleID) == [bundleID])
    #expect(system.resets.map(\.whileRunning) == [false])
  }

  /// The old copy's entry still works for it.
  @Test func whenTheNewBuildCantBePutInPlaceTheOldCopysEntryIsLeftAlone() {
    let system = system(running: "1", new: "2")
    system.replaceFailure = "busy"
    _ = restart(system)
    #expect(system.resets.isEmpty)
    #expect(system.launchedApps.map(\.path) == [FakeDaemonSystem.installedAppPath])
  }

  @Test func theEntryIsResetOnlyOnceTheNewBuildIsInPlace() {
    let system = system(running: "1", new: "2")
    _ = restart(system)
    #expect(system.replaced.count == 1)
    #expect(system.resets.count == 1)
  }

  @Test func aFailingResetDoesntStopTheNewTylerd() {
    let system = system(running: "1", new: "2")
    system.resetFailure = "no such app"
    guard case .message = restart(system) else {
      Issue.record("restart reported an error")
      return
    }
    #expect(system.launchedApps.count == 1)
  }
}

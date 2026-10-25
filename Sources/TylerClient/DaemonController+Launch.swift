import Foundation
import TylerProtocol
import TylerRuntime

/// What `start` launches: `Tyler.app` if there is one, else the bare `tylerd`.
extension DaemonController {
  private static let log = TylerLog(category: "ipc")

  enum LaunchTarget {
    /// The app at `path`, after putting the build staged at `staged` in its place, if set.
    case app(path: String, staged: String?)
    case executable
  }

  /// What `launch` did beyond launching, for the message.
  enum Install {
    case none
    case replaced(String)
    /// The new build couldn't be put in place, so the copy that was there runs.
    case keptOld(String, reason: String)

    var keptOld: Bool {
      if case .keptOld = self { return true }
      return false
    }
  }

  /// What to launch: the app if there is one, else the bare `tylerd`; an error if neither can be
  /// launched. A release runs from its copy in `~/Applications`: when that is missing or another
  /// build, the new one is staged beside it here, so that a failing copy fails before `restart`
  /// stops the old tylerd. A development build runs where it was built.
  func prepareLaunch() throws(DaemonError) -> LaunchTarget {
    if let app, system.isExecutable(atPath: app.executablePath) {
      if let source = system.appInfo(atPath: app.path), source.installsInApplications {
        guard system.appInfo(atPath: app.installedPath)?.build != source.build else {
          return .app(path: app.installedPath, staged: nil)
        }
        let staged = try system.stageApp(from: app.path, nextTo: app.installedPath)
        return .app(path: app.installedPath, staged: staged)
      }
      guard !isOutdated(app) else { throw .staleApp(app.path) }
      return .app(path: app.path, staged: nil)
    }
    guard system.isExecutable(atPath: serverPath) else { throw .missingServer(serverPath) }
    return .executable
  }

  /// Launches `target`. If a staged build can't be put in place, the copy that was there runs
  /// instead, which still takes on the windows a restart left parked. `staleEntry`, the bundle ID
  /// of an entry that can't work for the new build, is reset just before it launches, once it is
  /// in place: not for the old copy, whose entry still works.
  func launch(
    _ target: LaunchTarget, resettingEntryOf staleEntry: String? = nil
  ) throws(DaemonError) -> (pid: Int32?, install: Install) {
    switch target {
    case .app(let path, let staged):
      var install = Install.none
      if let staged {
        do {
          try system.replaceApp(at: path, with: staged)
          install = .replaced(path)
        } catch {
          guard system.isExecutable(atPath: AppLaunch.executable(in: path)) else { throw error }
          install = .keptOld(path, reason: error.description)
        }
      }
      if let staleEntry, !install.keptOld {
        do {
          _ = try system.resetAccessibility(bundleID: staleEntry)
        } catch {
          // The advice for a missing permission says what to do if the old entry stays.
          Self.log.warning("permission resetting failed - \(staleEntry) - \(error)")
        }
      }
      try system.launchApp(path, environment: app?.environment ?? [:])
      return (nil, install)
    case .executable:
      return (try system.spawn(serverPath, logPath: logPath), .none)
    }
  }

  /// Why the tylerd `target` starts won't hold the running one's grant.
  enum GrantChange: Equatable {
    /// It runs from another place: the bare tylerd and the app, or another copy of the app.
    case movesElsewhere
    /// Another ad-hoc build of the same app: macOS keeps its entry, switched on, but it no longer
    /// works for the new build (measured), so the entry is reset once the old one has quit.
    case newAdHocBuild(bundleID: String)
  }

  /// `nil` when the new tylerd holds the running one's grant: the same place and, for an ad-hoc
  /// app, the same build.
  func grantChange(from running: ServerStatus, to target: LaunchTarget) -> GrantChange? {
    guard running.executablePath == executablePath(target) else { return .movesElsewhere }
    return staleEntry(from: running, to: target).map { .newAdHocBuild(bundleID: $0) }
  }

  /// The bundle ID whose Accessibility entry can't work for the app `target` starts: it is signed
  /// ad hoc and isn't the build that runs, so an entry for its bundle ID belongs to another build
  /// (or there is none, and resetting it does no harm).
  func staleEntry(from running: ServerStatus, to target: LaunchTarget) -> String? {
    guard case .app(let path, let staged) = target,
      let new = system.appInfo(atPath: staged ?? path), new.isSignedAdHoc,
      let bundleID = new.bundleID,
      bundleID != running.appBundleID || new.build != running.appBuild
    else { return nil }
    return bundleID
  }

  func executablePath(_ target: LaunchTarget) -> String {
    switch target {
    case .app(let path, _): AppLaunch.executable(in: path)
    case .executable: serverPath
    }
  }

  /// Whether a development app's `tylerd` is older than the bare one next to it: `make` refreshes
  /// the bundle, a plain `swift build` only the bare `tylerd`.
  func isOutdated(_ app: AppLaunch) -> Bool {
    guard let bundled = system.modificationDate(ofFile: app.executablePath),
      let bare = system.modificationDate(ofFile: serverPath)
    else { return false }
    return bare > bundled
  }

  /// Whether the release next to `tyler` is another build than the copy in `~/Applications`
  /// that runs.
  func isInstalledCopyOutdated(running status: ServerStatus) -> Bool {
    guard let app, status.executablePath == AppLaunch.executable(in: app.installedPath),
      let source = system.appInfo(atPath: app.path), source.installsInApplications
    else { return false }
    return system.appInfo(atPath: app.installedPath)?.build != source.build
  }
}

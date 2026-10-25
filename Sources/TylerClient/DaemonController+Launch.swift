import Foundation
import TylerProtocol

/// What `start` launches: `Tyler.app` if there is one, else the bare `tylerd`.
extension DaemonController {
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

  /// Launches `target`. The pid of a spawned child (`nil` for the app, which LaunchServices
  /// starts), and what became of a staged build: if it can't be put in place, the copy that was
  /// there runs instead, which still takes on the windows a restart left parked.
  func launch(_ target: LaunchTarget) throws(DaemonError) -> (pid: Int32?, install: Install) {
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
      try system.launchApp(path, environment: app?.environment ?? [:])
      return (nil, install)
    case .executable:
      return (try system.spawn(serverPath, logPath: logPath), .none)
    }
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

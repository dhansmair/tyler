import Foundation

/// What `start` launches: `Tyler.app` if there is one, else the bare `tylerd`.
extension DaemonController {
  enum LaunchTarget {
    case app(AppLaunch)
    case executable
  }

  /// Launches `target`. The pid of a spawned child; `nil` for the app, which LaunchServices
  /// starts.
  func launch(_ target: LaunchTarget) throws(DaemonError) -> Int32? {
    switch target {
    case .app(let app):
      try system.launchApp(app.path, environment: app.environment)
      return nil
    case .executable:
      return try system.spawn(serverPath, logPath: logPath)
    }
  }

  /// The app if there is one, else the bare `tylerd`; an error if neither can be launched.
  func launchTarget() throws(DaemonError) -> LaunchTarget {
    if let app, system.isExecutable(atPath: app.executablePath) {
      guard !isOutdated(app) else { throw .staleApp(app.path) }
      return .app(app)
    }
    guard system.isExecutable(atPath: serverPath) else { throw .missingServer(serverPath) }
    return .executable
  }

  func executablePath(_ target: LaunchTarget) -> String {
    switch target {
    case .app(let app): app.executablePath
    case .executable: serverPath
    }
  }

  /// Whether the app's `tylerd` is older than the bare one next to it: `make` refreshes the
  /// bundle, a plain `swift build` only the bare `tylerd`.
  func isOutdated(_ app: AppLaunch) -> Bool {
    guard let bundled = system.modificationDate(ofFile: app.executablePath),
      let bare = system.modificationDate(ofFile: serverPath)
    else { return false }
    return bare > bundled
  }
}

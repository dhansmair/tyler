import Foundation
import TylerCore
import TylerRuntime

/// What `tylerd` reports about itself for `tyler status`, `stop` and `restart`.
package struct ServerStatus: Codable, Equatable, Sendable {
  package enum Tiling: String, Codable, Sendable {
    case waitingForPermission
    case on
    case off
  }

  package var pid: Int32
  /// The `tylerd` binary that is running.
  package var executablePath: String
  /// When that binary was last modified as of the server's start. If the file on disk is newer,
  /// it has been rebuilt since, and the running server is out of date.
  package var executableModified: Date?
  package var startedAt: Date
  package var configPath: String
  package var tiling: Tiling
  /// Whether the server leaves its windows in place for the next tylerd when asked to hand over
  /// (SIGUSR1). Optional so a server from before hand-over existed decodes as `nil`: such a
  /// server would die on SIGUSR1 without cleaning up, so restart sends it SIGTERM instead.
  package var keepsWindowsOnRestart: Bool?
  /// Whether the server, asked to hand over with SIGUSR2, puts every window back first and still
  /// hands its workspaces over. Optional for the same reason: an older server would die on it.
  package var putsWindowsBackOnHandOver: Bool?
  /// The server's `TylerVersion`; `nil` from a server older than 0.1.0.
  package var version: String?
  /// The settings `tyler config set` changed since the config was last read; `nil` from a server
  /// without `config set`.
  package var configChanges: [String]?
  /// Whether tylerd can reach the windows; `nil` from a server older than this check.
  package var access: WindowAccess?
  /// The event listeners tylerd keeps; `nil` from a server older than this report.
  package var input: [InputListener]?
  /// The app whose Accessibility grant tylerd runs under when it is one, as System Settings lists
  /// it (`Tyler.app`); `nil` when the app that started it holds the grant (a terminal), or from an
  /// older server.
  package var appName: String?

  package init(
    pid: Int32,
    executablePath: String,
    executableModified: Date?,
    startedAt: Date,
    configPath: String,
    tiling: Tiling = .waitingForPermission,
    keepsWindowsOnRestart: Bool? = nil,
    putsWindowsBackOnHandOver: Bool? = nil,
    version: String? = nil,
    configChanges: [String]? = nil,
    access: WindowAccess? = nil,
    input: [InputListener]? = nil,
    appName: String? = nil
  ) {
    self.pid = pid
    self.executablePath = executablePath
    self.executableModified = executableModified
    self.startedAt = startedAt
    self.configPath = configPath
    self.tiling = tiling
    self.keepsWindowsOnRestart = keepsWindowsOnRestart
    self.putsWindowsBackOnHandOver = putsWindowsBackOnHandOver
    self.version = version
    self.configChanges = configChanges
    self.access = access
    self.input = input
    self.appName = appName
  }
}

import Foundation

/// What `tylerd` reports about itself for `tyler status`, `stop` and `restart`.
public struct ServerStatus: Codable, Equatable, Sendable {
  public enum Tiling: String, Codable, Sendable {
    case waitingForPermission
    case on
    case off
  }

  public var pid: Int32
  /// The `tylerd` binary that is running.
  public var executablePath: String
  /// When that binary was last modified as of the server's start. If the file on disk is newer,
  /// it has been rebuilt since, and the running server is out of date.
  public var executableModified: Date?
  public var startedAt: Date
  public var configPath: String
  public var tiling: Tiling
  /// Whether the server leaves its windows in place for the next tylerd when asked to hand over
  /// (SIGUSR1). Optional so a server from before hand-over existed decodes as `nil`: such a
  /// server would die on SIGUSR1 without cleaning up, so restart sends it SIGTERM instead.
  public var keepsWindowsOnRestart: Bool?

  public init(
    pid: Int32,
    executablePath: String,
    executableModified: Date?,
    startedAt: Date,
    configPath: String,
    tiling: Tiling = .waitingForPermission,
    keepsWindowsOnRestart: Bool? = nil
  ) {
    self.pid = pid
    self.executablePath = executablePath
    self.executableModified = executableModified
    self.startedAt = startedAt
    self.configPath = configPath
    self.tiling = tiling
    self.keepsWindowsOnRestart = keepsWindowsOnRestart
  }
}

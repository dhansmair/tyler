import Foundation

public enum Paths {
  /// `$TYLER_SOCKET` if set and non-empty, otherwise `~/.tyler/tyler.sock`.
  public static func socketPath(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: String = NSHomeDirectory()
  ) -> String {
    if let override = environment["TYLER_SOCKET"], !override.isEmpty {
      return override
    }
    return home + "/.tyler/tyler.sock"
  }

  /// Where `tyler start` sends the server's output: the socket path with `.log` instead of
  /// `.sock` (`~/.tyler/tyler.log` by default), so separate instances keep separate logs.
  public static func logPath(socketPath: String = socketPath()) -> String {
    let base = socketPath.hasSuffix(".sock") ? String(socketPath.dropLast(5)) : socketPath
    return base + ".log"
  }

  /// `$TYLER_CONFIG` if set and non-empty, otherwise `~/.config/tyler/tyler.toml`.
  public static func configPath(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: String = NSHomeDirectory()
  ) -> String {
    if let override = environment["TYLER_CONFIG"], !override.isEmpty {
      return override
    }
    return home + "/.config/tyler/tyler.toml"
  }
}

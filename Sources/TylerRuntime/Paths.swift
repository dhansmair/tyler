import Foundation

package enum Paths {
  /// `$TYLER_SOCKET` if set and non-empty, otherwise `~/.tyler/tyler.sock`.
  package static func socketPath(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: String = NSHomeDirectory()
  ) -> String {
    override("TYLER_SOCKET", in: environment) ?? home + "/.tyler/tyler.sock"
  }

  /// Where `tyler start` sends the server's output: the socket path with `.log` instead of
  /// `.sock` (`~/.tyler/tyler.log` by default), so separate instances keep separate logs.
  package static func logPath(socketPath: String = socketPath()) -> String {
    base(of: socketPath) + ".log"
  }

  /// Where tylerd leaves its workspaces for the next tylerd when it restarts: the socket path
  /// with `.state.json` instead of `.sock` (`~/.tyler/tyler.state.json` by default).
  package static func statePath(socketPath: String = socketPath()) -> String {
    base(of: socketPath) + ".state.json"
  }

  /// `$TYLER_CONFIG` if set and non-empty, otherwise `~/.config/tyler/tyler.toml`.
  package static func configPath(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: String = NSHomeDirectory()
  ) -> String {
    override("TYLER_CONFIG", in: environment) ?? home + "/.config/tyler/tyler.toml"
  }

  /// The variable's value, unless it is unset or empty.
  private static func override(_ name: String, in environment: [String: String]) -> String? {
    environment[name].flatMap { $0.isEmpty ? nil : $0 }
  }

  /// The socket path without its `.sock` extension: the stem the log and state files share.
  private static func base(of socketPath: String) -> String {
    let suffix = ".sock"
    return socketPath.hasSuffix(suffix) ? String(socketPath.dropLast(suffix.count)) : socketPath
  }
}

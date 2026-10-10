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
}

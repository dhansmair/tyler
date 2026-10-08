import Foundation

public enum Paths {
  /// `$MWM_SOCKET` if set and non-empty, otherwise `~/.mwm/mwm.sock`.
  public static func socketPath(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: String = NSHomeDirectory()
  ) -> String {
    if let override = environment["MWM_SOCKET"], !override.isEmpty {
      return override
    }
    return home + "/.mwm/mwm.sock"
  }
}

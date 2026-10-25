import Foundation

/// A `Tyler.app` that `tyler start` launches through LaunchServices, so tylerd is responsible
/// for itself and holds its own Accessibility grant instead of the terminal's.
package struct AppLaunch: Equatable, Sendable {
  /// What a tylerd spawned from the terminal inherited and still needs: where its config is,
  /// and what `config edit` runs.
  private static let passedVariables = ["TYLER_CONFIG", "PATH", "EDITOR", "VISUAL"]

  package let path: String
  /// Passed with `open --env`: LaunchServices doesn't hand the terminal's environment on.
  package let environment: [String: String]

  package var executablePath: String { path + "/Contents/MacOS/tylerd" }

  package init(path: String, environment: [String: String]) {
    self.path = path
    self.environment = environment
  }

  /// The `Tyler.app` in the same folder as the `tyler` binary at `client`, after resolving
  /// symlinks, told the socket `tyler` uses. LaunchServices starts the app in `/`, so relative
  /// paths are made absolute against `workingDirectory`, where `tyler` runs.
  package static func nextTo(
    _ client: URL, socketPath: String, environment: [String: String], workingDirectory: String
  ) -> AppLaunch {
    let path = client.resolvingSymlinksInPath().deletingLastPathComponent()
      .appendingPathComponent("Tyler.app").path
    var passed = environment.filter { passedVariables.contains($0.key) && !$0.value.isEmpty }
    passed["TYLER_SOCKET"] = socketPath
    for name in ["TYLER_SOCKET", "TYLER_CONFIG"] {
      guard let value = passed[name], !value.hasPrefix("/") else { continue }
      passed[name] =
        URL(
          fileURLWithPath: value,
          relativeTo: URL(fileURLWithPath: workingDirectory, isDirectory: true)
        )
        .standardizedFileURL.path
    }
    return AppLaunch(path: path, environment: passed)
  }
}

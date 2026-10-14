import Foundation
import TylerCore

/// Where the config comes from. `read` returns `nil` when there is no config file, which means
/// the defaults apply.
package struct ConfigSource: Sendable {
  /// Shown in messages, so the user knows which file was read.
  package let path: String
  package let read: @Sendable () throws(ConfigError) -> Config?

  package init(path: String, read: @escaping @Sendable () throws(ConfigError) -> Config?) {
    self.path = path
    self.read = read
  }

  /// Reads the config for startup, where no file and a broken file both mean the defaults.
  package func load() -> ConfigLoad {
    do {
      return try read().map(ConfigLoad.loaded) ?? .missing
    } catch {
      return .broken(error)
    }
  }

  /// The `tyler.toml` at `path`.
  package static func file(at path: String) -> ConfigSource {
    ConfigSource(path: path) { () throws(ConfigError) -> Config? in
      guard FileManager.default.fileExists(atPath: path) else { return nil }
      let text: String
      do {
        text = try String(contentsOfFile: path, encoding: .utf8)
      } catch {
        throw .unreadable(error.localizedDescription)
      }
      return try Config.parse(text)
    }
  }
}

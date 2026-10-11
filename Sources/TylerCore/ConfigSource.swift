import Foundation

/// What tylerd found when it read its config at startup.
public enum ConfigLoad: Equatable, Sendable {
  case loaded(Config)
  /// There is no config file, so the defaults apply.
  case missing
  /// The file can't be used. tylerd starts with the defaults rather than not at all, and
  /// `tyler reload` picks the file up once it is fixed.
  case broken(ConfigError)

  /// The config to start with.
  public var config: Config {
    if case .loaded(let config) = self { config } else { Config() }
  }
}

/// Where the config comes from. `read` returns `nil` when there is no config file, which means
/// the defaults apply.
public struct ConfigSource: Sendable {
  /// Shown in messages, so the user knows which file was read.
  public let path: String
  public let read: @Sendable () throws(ConfigError) -> Config?

  public init(path: String, read: @escaping @Sendable () throws(ConfigError) -> Config?) {
    self.path = path
    self.read = read
  }

  /// Reads the config for startup, where no file and a broken file both mean the defaults.
  public func load() -> ConfigLoad {
    do {
      return try read().map(ConfigLoad.loaded) ?? .missing
    } catch {
      return .broken(error)
    }
  }

  /// The `tyler.toml` at `path`.
  public static func file(at path: String) -> ConfigSource {
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

/// What tylerd found when it read its config at startup.
package enum ConfigLoad: Equatable, Sendable {
  case loaded(Config)
  /// There is no config file, so the defaults apply.
  case missing
  /// The file can't be used. tylerd starts with the defaults rather than not at all, and
  /// `tyler config reload` picks the file up once it is fixed.
  case broken(ConfigError)

  /// The config to start with.
  package var config: Config {
    if case .loaded(let config) = self { config } else { Config() }
  }
}

import TylerRuntime

extension Config {
  /// What tylerd writes to its log file.
  package struct Log: Equatable, Sendable {
    /// The least level written to `~/.tyler/tyler.log` (the unified log gets more).
    package var level: LogLevel

    package init(level: LogLevel = .warning) {
      self.level = level
    }
  }
}

extension Config.Log {
  init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read("log", value, into: Self(), Self.settings)
  }

  /// The keys of `[log]`, and how each is read.
  static let settings: [Setting<Self>] = [levelSetting]

  private static let levelSetting = Setting<Self>(
    "level",
    read: { log, value, name throws(ConfigError) in
      let names = LogLevel.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
      guard case .string(let text) = value, let level = LogLevel(rawValue: text) else {
        throw .invalid("\(name) must be one of \(names)")
      }
      log.level = level
    }, write: { .string($0.level.rawValue) })
}

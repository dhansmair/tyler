import Foundation

/// tyler's settings, read from `tyler.toml`. Every setting has a default, so an empty or
/// missing file is valid, and the file only lists what differs.
public struct Config: Equatable, Sendable {
  /// Space around tiled windows, in whole points.
  public struct Gaps: Equatable, Sendable {
    /// Between neighbouring windows.
    public var inner: Int
    /// Between the windows and the edge of the display's visible area.
    public var outer: Int

    public init(inner: Int = 0, outer: Int = 0) {
      self.inner = inner
      self.outer = outer
    }
  }

  public var gaps: Gaps

  public init(gaps: Gaps = Gaps()) {
    self.gaps = gaps
  }
}

/// Why a config file could not be used.
public enum ConfigError: Error, Equatable, Sendable, CustomStringConvertible {
  case unreadable(String)
  case syntax(TOMLError)
  /// Valid TOML, but not a valid config: an unknown key, a wrong type, a value out of range.
  case invalid(String)

  public var description: String {
    switch self {
    case .unreadable(let reason): "cannot read the file: \(reason)"
    case .syntax(let error): error.description
    case .invalid(let message): message
    }
  }
}

extension Config {
  /// Parses a `tyler.toml` document. Unknown keys are errors, so a typo doesn't go unnoticed.
  public static func parse(_ text: String) throws(ConfigError) -> Config {
    let document: [String: TOMLValue]
    do {
      document = try TOML.parse(text)
    } catch {
      throw .syntax(error)
    }
    var config = Config()
    for (key, value) in document.sorted(by: { $0.key < $1.key }) {
      switch key {
      case "gaps": config.gaps = try Gaps(value)
      default: throw .invalid("unknown setting '\(key)'")
      }
    }
    return config
  }
}

extension Config.Gaps {
  fileprivate init(_ value: TOMLValue) throws(ConfigError) {
    guard case .table(let table) = value else {
      throw .invalid("gaps must be a table: write [gaps] and put inner and outer below it")
    }
    self.init()
    for (key, value) in table.sorted(by: { $0.key < $1.key }) {
      switch key {
      case "inner": inner = try Self.points(value, for: key)
      case "outer": outer = try Self.points(value, for: key)
      default: throw .invalid("unknown setting 'gaps.\(key)' (use inner or outer)")
      }
    }
  }

  private static func points(_ value: TOMLValue, for key: String) throws(ConfigError) -> Int {
    guard case .integer(let points) = value, points >= 0 else {
      throw .invalid("gaps.\(key) must be a whole number of points, 0 or more")
    }
    return points
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

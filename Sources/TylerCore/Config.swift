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

  /// How tiled windows follow the mouse.
  public struct Mouse: Equatable, Sendable {
    public static let followIntervalRange = 0...1000

    /// The least time, in milliseconds, between two steps of the layout following a window
    /// resized with the mouse. Each step moves every other window, one round trip to its app
    /// each, so with slow apps a shorter interval lets the steps fall behind the mouse. 0
    /// follows every resize the app reports.
    public var followInterval: Int

    public init(followInterval: Int = 50) {
      self.followInterval = followInterval
    }
  }

  /// The workspaces of each display.
  public struct Workspaces: Equatable, Sendable {
    public static let countRange = 1...10

    /// How many workspaces a display's stack has.
    public var count: Int

    public init(count: Int = WorkspaceStack.defaultCount) {
      self.count = count
    }
  }

  public var gaps: Gaps
  public var mouse: Mouse
  public var workspaces: Workspaces

  public init(gaps: Gaps = Gaps(), mouse: Mouse = Mouse(), workspaces: Workspaces = Workspaces()) {
    self.gaps = gaps
    self.mouse = mouse
    self.workspaces = workspaces
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
      case "mouse": config.mouse = try Mouse(value)
      case "workspaces": config.workspaces = try Workspaces(value)
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

extension Config.Mouse {
  fileprivate init(_ value: TOMLValue) throws(ConfigError) {
    guard case .table(let table) = value else {
      throw .invalid("mouse must be a table: write [mouse] and put follow-interval below it")
    }
    self.init()
    for (key, value) in table.sorted(by: { $0.key < $1.key }) {
      switch key {
      case "follow-interval":
        let range = Self.followIntervalRange
        guard case .integer(let milliseconds) = value, range.contains(milliseconds) else {
          throw .invalid(
            "mouse.follow-interval must be a whole number of milliseconds, "
              + "\(range.lowerBound) to \(range.upperBound)")
        }
        followInterval = milliseconds
      default: throw .invalid("unknown setting 'mouse.\(key)' (use follow-interval)")
      }
    }
  }
}

extension Config.Workspaces {
  fileprivate init(_ value: TOMLValue) throws(ConfigError) {
    guard case .table(let table) = value else {
      throw .invalid("workspaces must be a table: write [workspaces] and put count below it")
    }
    self.init()
    for (key, value) in table.sorted(by: { $0.key < $1.key }) {
      switch key {
      case "count":
        let range = Self.countRange
        guard case .integer(let number) = value, range.contains(number) else {
          throw .invalid(
            "workspaces.count must be a whole number, \(range.lowerBound) to \(range.upperBound)")
        }
        count = number
      default: throw .invalid("unknown setting 'workspaces.\(key)' (use count)")
      }
    }
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

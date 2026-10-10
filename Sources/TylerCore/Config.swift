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

  /// Trackpad gestures.
  public struct Gestures: Equatable, Sendable {
    public static let fingersRange = 3...4
    public static let swipeDistanceRange = 0.1...1.0

    /// Whether a sideways swipe moves between workspaces.
    public var swipe: Bool
    /// How many fingers the swipe takes. macOS has its own swipes with three and four fingers
    /// (between full-screen apps, between pages); the one tyler uses should be free there.
    public var fingers: Int
    /// How far the fingers travel, in trackpad widths, to slide a whole workspace across.
    public var swipeDistance: Double

    public init(swipe: Bool = true, fingers: Int = 3, swipeDistance: Double = 0.3) {
      self.swipe = swipe
      self.fingers = fingers
      self.swipeDistance = swipeDistance
    }
  }

  public var gaps: Gaps
  public var gestures: Gestures
  public var mouse: Mouse
  public var workspaces: Workspaces
  /// The workspace (1-based) new windows of an app open on, keyed by bundle ID or app name in
  /// lower case.
  public var assignments: [String: Int]

  public init(
    gaps: Gaps = Gaps(), gestures: Gestures = Gestures(), mouse: Mouse = Mouse(),
    workspaces: Workspaces = Workspaces(), assignments: [String: Int] = [:]
  ) {
    self.gaps = gaps
    self.gestures = gestures
    self.mouse = mouse
    self.workspaces = workspaces
    self.assignments = assignments
  }

  /// The 1-based workspace that new windows of this app are assigned to, if any. A rule for the
  /// bundle ID wins over one for the app name; both match regardless of case.
  public func assignedWorkspace(bundleID: String?, appName: String) -> Int? {
    if let bundleID, let number = assignments[bundleID.lowercased()] { return number }
    return assignments[appName.lowercased()]
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
    var assign: TOMLValue?
    for (key, value) in document.sorted(by: { $0.key < $1.key }) {
      switch key {
      case "assign": assign = value
      case "gaps": config.gaps = try Gaps(value)
      case "gestures": config.gestures = try Gestures(value)
      case "mouse": config.mouse = try Mouse(value)
      case "workspaces": config.workspaces = try Workspaces(value)
      default: throw .invalid("unknown setting '\(key)'")
      }
    }
    // Read last: the numbers are checked against the workspace count.
    if let assign {
      config.assignments = try Self.assignments(assign, count: config.workspaces.count)
    }
    return config
  }

  /// `[assign]`: app (bundle ID or name) = workspace number.
  private static func assignments(
    _ value: TOMLValue, count: Int
  ) throws(ConfigError) -> [String: Int] {
    guard case .table(let table) = value else {
      throw .invalid("assign must be a table: write [assign] and put app = workspace below it")
    }
    var assignments: [String: Int] = [:]
    for (app, value) in table.sorted(by: { $0.key < $1.key }) {
      if case .table = value {
        throw .invalid("assign.\(app) is a table: quote app names and bundle IDs that contain dots")
      }
      guard case .integer(let number) = value, number >= 1 else {
        throw .invalid("assign.\(app) must be a workspace number, 1 or more")
      }
      guard number <= count else {
        throw .invalid(
          "assign.\(app) = \(number), but there are only \(count) workspaces (workspaces.count)")
      }
      guard assignments.updateValue(number, forKey: app.lowercased()) == nil else {
        throw .invalid("assign.\(app) is set twice (app names and bundle IDs ignore case)")
      }
    }
    return assignments
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

extension Config.Gestures {
  fileprivate init(_ value: TOMLValue) throws(ConfigError) {
    guard case .table(let table) = value else {
      throw .invalid(
        "gestures must be a table: write [gestures] and put swipe, fingers and swipe-distance below it"
      )
    }
    self.init()
    for (key, value) in table.sorted(by: { $0.key < $1.key }) {
      switch key {
      case "swipe": swipe = try Self.swipe(value)
      case "fingers": fingers = try Self.fingers(value)
      case "swipe-distance": swipeDistance = try Self.swipeDistance(value)
      default:
        throw .invalid("unknown setting 'gestures.\(key)' (use swipe, fingers or swipe-distance)")
      }
    }
  }

  private static func swipe(_ value: TOMLValue) throws(ConfigError) -> Bool {
    guard case .boolean(let isOn) = value else {
      throw .invalid("gestures.swipe must be true or false")
    }
    return isOn
  }

  private static func fingers(_ value: TOMLValue) throws(ConfigError) -> Int {
    guard case .integer(let count) = value, fingersRange.contains(count) else {
      throw .invalid(
        "gestures.fingers must be \(fingersRange.lowerBound) or \(fingersRange.upperBound)")
    }
    return count
  }

  private static func swipeDistance(_ value: TOMLValue) throws(ConfigError) -> Double {
    let range = swipeDistanceRange
    let distance: Double? =
      switch value {
      case .float(let number): number
      case .integer(let number): Double(number)
      default: nil
      }
    guard let distance, range.contains(distance) else {
      throw .invalid(
        "gestures.swipe-distance must be a number of trackpad widths, "
          + "\(range.lowerBound) to \(range.upperBound)")
    }
    return distance
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

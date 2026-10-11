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
    static let followIntervalRange = 0...1000

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
    static let countRange = 1...10

    /// How many workspaces a display's row has.
    public var count: Int

    public init(count: Int = WorkspaceRow.defaultCount) {
      self.count = count
    }
  }

  /// Trackpad gestures.
  public struct Gestures: Equatable, Sendable {
    static let fingersRange = 3...4
    static let swipeDistanceRange = 0.1...1.0

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
  public var indicator: Indicator
  public var mouse: Mouse
  public var workspaces: Workspaces
  /// The workspace numbers of each display, by display number (1 is the primary); empty when the
  /// config file has no `[displays]` (see `workspaceNumbers`).
  public var displays: [Int: [Int]]
  /// The number of the workspace new windows of an app open on, keyed by bundle ID or app name
  /// in lower case.
  public var assignments: [String: Int]

  public init(
    gaps: Gaps = Gaps(), gestures: Gestures = Gestures(), indicator: Indicator = Indicator(),
    mouse: Mouse = Mouse(), workspaces: Workspaces = Workspaces(), displays: [Int: [Int]] = [:],
    assignments: [String: Int] = [:]
  ) {
    self.gaps = gaps
    self.gestures = gestures
    self.indicator = indicator
    self.mouse = mouse
    self.workspaces = workspaces
    self.displays = displays
    self.assignments = assignments
  }

  /// The 1-based workspace that new windows of this app are assigned to, if any. A rule for the
  /// bundle ID wins over one for the app name; both match regardless of case.
  public func assignedWorkspace(bundleID: String?, appName: String) -> Int? {
    Self.lookUp(assignments, bundleID: bundleID, appName: appName)
  }

  /// An app's entry in a table keyed by bundle ID or app name in lower case. The bundle ID wins;
  /// both match regardless of case.
  static func lookUp<Value>(
    _ table: [String: Value], bundleID: String?, appName: String
  ) -> Value? {
    if let bundleID, let value = table[bundleID.lowercased()] { return value }
    return table[appName.lowercased()]
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
      case "assign", "displays": break  // read below
      case "gaps": config.gaps = try Gaps(value)
      case "gestures": config.gestures = try Gestures(value)
      case "indicator": config.indicator = try Indicator(value)
      case "mouse": config.mouse = try Mouse(value)
      case "workspaces": config.workspaces = try Workspaces(value)
      default: throw .invalid("unknown setting '\(key)'")
      }
    }
    try config.readWorkspaceNumbers(from: document)
    return config
  }

  /// `[displays]`, then `[assign]`, whose numbers are checked against it.
  private mutating func readWorkspaceNumbers(
    from document: [String: TOMLValue]
  ) throws(ConfigError) {
    if let value = document["displays"] { displays = try Self.displays(value) }
    if let value = document["assign"] {
      assignments = try Self.assignments(value, displays: displays)
    }
  }

  /// `[assign]`: app (bundle ID or name) = workspace number.
  private static func assignments(
    _ value: TOMLValue, displays: [Int: [Int]]
  ) throws(ConfigError) -> [String: Int] {
    let listed = Set(displays.values.joined())
    guard case .table(let table) = value else {
      throw .invalid("assign must be a table: write [assign] and put app = workspace below it")
    }
    var assignments: [String: Int] = [:]
    for (app, value) in table.sorted(by: { $0.key < $1.key }) {
      if case .table = value {
        throw .invalid("assign.\(app) is a table: quote app names and bundle IDs that contain dots")
      }
      guard case .integer(let number) = value, workspaceNumberRange.contains(number) else {
        throw .invalid(
          "assign.\(app) must be a workspace number, \(workspaceNumberRange.lowerBound) to "
            + "\(workspaceNumberRange.upperBound)")
      }
      guard listed.isEmpty || listed.contains(number) else {
        throw .invalid("assign.\(app) = \(number), but [displays] lists no workspace \(number)")
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
    self = try Section.read(
      "gaps", value, into: Self(),
      Setting("inner") { gaps, value, name throws(ConfigError) in
        gaps.inner = try Section.points(value, name)
      },
      Setting("outer") { gaps, value, name throws(ConfigError) in
        gaps.outer = try Section.points(value, name)
      })
  }
}

extension Config.Gestures {
  fileprivate init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read(
      "gestures", value, into: Self(),
      Setting("swipe") { gestures, value, name throws(ConfigError) in
        gestures.swipe = try Section.boolean(value, name)
      },
      Setting("fingers") { gestures, value, name throws(ConfigError) in
        gestures.fingers = try Section.integer(value, name, in: Self.fingersRange)
      },
      Setting("swipe-distance") { gestures, value, name throws(ConfigError) in
        gestures.swipeDistance = try Section.number(
          value, name, in: Self.swipeDistanceRange, unit: "trackpad widths")
      })
  }
}

extension Config.Mouse {
  fileprivate init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read(
      "mouse", value, into: Self(),
      Setting("follow-interval") { mouse, value, name throws(ConfigError) in
        mouse.followInterval = try Section.integer(
          value, name, in: Self.followIntervalRange, unit: "milliseconds")
      })
  }
}

extension Config.Workspaces {
  fileprivate init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read(
      "workspaces", value, into: Self(),
      Setting("count") { workspaces, value, name throws(ConfigError) in
        workspaces.count = try Section.integer(value, name, in: Self.countRange)
      })
  }
}

/// One key of a config section, and how its value goes into the section. `read` also gets the
/// setting's full name (`gaps.inner`), for its error messages.
struct Setting<Value> {
  typealias Read = (inout Value, TOMLValue, _ name: String) throws(ConfigError) -> Void

  let key: String
  let read: Read

  init(_ key: String, read: @escaping Read) {
    self.key = key
    self.read = read
  }
}

/// Reading a `[section]` table and its values. The error messages name the section's keys from
/// its settings, so they can't drift from what is accepted.
enum Section {
  static func read<Value>(
    _ name: String, _ value: TOMLValue, into defaults: Value, _ settings: Setting<Value>...
  ) throws(ConfigError) -> Value {
    let keys = settings.map(\.key)
    guard case .table(let table) = value else {
      throw .invalid(
        "\(name) must be a table: write [\(name)] and put \(list(keys, "and")) below it")
    }
    var section = defaults
    for (key, value) in table.sorted(by: { $0.key < $1.key }) {
      guard let setting = settings.first(where: { $0.key == key }) else {
        throw .invalid("unknown setting '\(name).\(key)' (use \(list(keys, "or")))")
      }
      try setting.read(&section, value, "\(name).\(key)")
    }
    return section
  }

  static func boolean(_ value: TOMLValue, _ name: String) throws(ConfigError) -> Bool {
    guard case .boolean(let isOn) = value else { throw .invalid("\(name) must be true or false") }
    return isOn
  }

  static func points(_ value: TOMLValue, _ name: String) throws(ConfigError) -> Int {
    guard case .integer(let points) = value, points >= 0 else {
      throw .invalid("\(name) must be a whole number of points, 0 or more")
    }
    return points
  }

  /// A whole number in `range`. A range of two values reads "3 or 4"; others name the unit.
  static func integer(
    _ value: TOMLValue, _ name: String, in range: ClosedRange<Int>, unit: String? = nil
  ) throws(ConfigError) -> Int {
    guard case .integer(let number) = value, range.contains(number) else {
      if range.count == 2 {
        throw .invalid("\(name) must be \(range.lowerBound) or \(range.upperBound)")
      }
      let kind = unit.map { "a whole number of \($0)" } ?? "a whole number"
      throw .invalid("\(name) must be \(kind), \(range.lowerBound) to \(range.upperBound)")
    }
    return number
  }

  /// A number in `range`; whole numbers count too.
  static func number(
    _ value: TOMLValue, _ name: String, in range: ClosedRange<Double>, unit: String
  ) throws(ConfigError) -> Double {
    let number: Double? =
      switch value {
      case .float(let number): number
      case .integer(let number): Double(number)
      default: nil
      }
    guard let number, range.contains(number) else {
      throw .invalid(
        "\(name) must be a number of \(unit), \(range.lowerBound) to \(range.upperBound)")
    }
    return number
  }

  /// "a", "a and b", "a, b and c".
  private static func list(_ items: [String], _ conjunction: String) -> String {
    guard let last = items.last, items.count > 1 else { return items.first ?? "" }
    return items.dropLast().joined(separator: ", ") + " \(conjunction) " + last
  }
}

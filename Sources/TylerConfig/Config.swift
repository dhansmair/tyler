import Foundation
import TylerCore

/// tyler's settings, read from `tyler.toml`. Every setting has a default, so an empty or
/// missing file is valid, and the file only lists what differs.
package struct Config: Equatable, Sendable {
  /// Space around tiled windows, in whole points.
  package struct Gaps: Equatable, Sendable {
    /// Between neighbouring windows.
    package var inner: Int
    /// Between the windows and the edge of the display's visible area.
    package var outer: Int

    package init(inner: Int = 0, outer: Int = 0) {
      self.inner = inner
      self.outer = outer
    }
  }

  /// How tiled windows follow the mouse, focus follows it, and a modifier moves and resizes them.
  package struct Mouse: Equatable, Sendable {
    static let followIntervalRange = 0...1000
    static let focusDelayRange = 0...1000

    /// The least time, in milliseconds, between two steps of the layout following a window
    /// resized with the mouse. Each step moves every other window, one round trip to its app
    /// each, so with slow apps a shorter interval lets the steps fall behind the mouse. 0
    /// follows every resize the app reports.
    package var followInterval: Int
    /// Whether the pointer coming to rest over a window focuses it.
    package var focusFollows: Bool
    /// How long, in milliseconds, the pointer must rest before focus follows it, so a pointer
    /// sweeping across windows doesn't focus each on the way.
    package var focusDelay: Int
    /// The keys that, held while dragging anywhere in a window, move it (left button) or resize
    /// it (right button). Empty turns this off.
    package var modifier: ModifierKeys
    /// Whether dragging the gap between two tiled windows moves the divider between them.
    package var gapResize: Bool

    package init(
      followInterval: Int = 16, focusFollows: Bool = false, focusDelay: Int = 100,
      modifier: ModifierKeys = .option, gapResize: Bool = true
    ) {
      self.followInterval = followInterval
      self.focusFollows = focusFollows
      self.focusDelay = focusDelay
      self.modifier = modifier
      self.gapResize = gapResize
    }
  }

  /// The workspaces of each display.
  package struct Workspaces: Equatable, Sendable {
    static let countRange = 1...10

    /// How many workspaces a display's row has.
    package var count: Int

    package init(count: Int = WorkspaceRow.defaultCount) {
      self.count = count
    }
  }

  /// Trackpad gestures.
  package struct Gestures: Equatable, Sendable {
    static let fingersRange = 3...4
    static let swipeDistanceRange = 0.1...1.0

    /// Whether a sideways swipe moves between workspaces.
    package var swipe: Bool
    /// How many fingers the swipe takes. macOS has its own swipes with three and four fingers
    /// (between full-screen apps, between pages); the one tyler uses should be free there.
    package var fingers: Int
    /// How far the fingers travel, in trackpad widths, to slide a whole workspace across.
    package var swipeDistance: Double

    package init(swipe: Bool = true, fingers: Int = 3, swipeDistance: Double = 0.3) {
      self.swipe = swipe
      self.fingers = fingers
      self.swipeDistance = swipeDistance
    }
  }

  package var editor: Editor
  package var gaps: Gaps
  package var gestures: Gestures
  package var indicators: Indicators
  package var layouts: Layouts
  package var log: Log
  package var mouse: Mouse
  package var workspaces: Workspaces
  /// The workspace numbers of each display that lists its own, by display number (1 is the
  /// primary); see `workspaceNumbers`.
  package var displays: [Int: [Int]]
  /// The settings of each app the config file names, keyed by bundle ID or app name in lower
  /// case.
  package var apps: [String: App]

  package init(
    editor: Editor = Editor(), gaps: Gaps = Gaps(), gestures: Gestures = Gestures(),
    indicators: Indicators = Indicators(),
    layouts: Layouts = Layouts(), log: Log = Log(), mouse: Mouse = Mouse(),
    workspaces: Workspaces = Workspaces(),
    displays: [Int: [Int]] = [:], apps: [String: App] = [:]
  ) {
    self.editor = editor
    self.gaps = gaps
    self.gestures = gestures
    self.indicators = indicators
    self.layouts = layouts
    self.log = log
    self.mouse = mouse
    self.workspaces = workspaces
    self.displays = displays
    self.apps = apps
  }
}

extension Config {
  /// Every setting the file accepts, by its full name (`gaps.inner`), and the tables keyed by
  /// app or display (`apps`, `displays`). Keep in step with `parse`.
  static var settingNames: [String] {
    func names<Value>(_ section: String, _ settings: [Setting<Value>]) -> [String] {
      settings.map { "\(section).\($0.key)" }
    }
    return names("editor", Editor.settings) + names("gaps", Gaps.settings)
      + names("gestures", Gestures.settings)
      + names("indicators.text", Indicators.Text.settings)
      + names("indicators.map", Indicators.Map.settings) + names("layouts", Layouts.settings)
      + names("log", Log.settings) + names("mouse", Mouse.settings)
      + names("workspaces", Workspaces.settings)
      + names("displays.*", Display.settings) + names("apps.*", App.settings)
  }

  /// Parses a `tyler.toml` document. Unknown keys are errors, so a typo doesn't go unnoticed.
  package static func parse(_ text: String) throws(ConfigError) -> Config {
    let document: [String: TOMLValue]
    do {
      document = try TOML.parse(text)
    } catch {
      throw .syntax(error)
    }
    return try parse(document: document)
  }

  /// The config a parsed `tyler.toml` sets, checked as `parse` checks the file.
  package static func parse(document: [String: TOMLValue]) throws(ConfigError) -> Config {
    var config = Config()
    for (key, value) in document.sorted(by: { $0.key < $1.key }) {
      if key == "apps" || key == "displays" { continue }  // read below
      guard let section = sections.first(where: { $0.key == key }) else {
        throw .invalid("unknown setting '\(key)'")
      }
      try section.read(&config, value, key)
    }
    try config.readWorkspaceNumbers(from: document)
    return config
  }

  /// The tables other than `[apps]` and `[displays]`, each read and written by its own settings.
  static let sections: [Setting<Config>] = [
    Setting(
      "editor", read: { config, value, _ throws(ConfigError) in config.editor = try Editor(value) },
      write: { Section.document($0.editor, Editor.settings) }),
    Setting(
      "gaps", read: { config, value, _ throws(ConfigError) in config.gaps = try Gaps(value) },
      write: { Section.document($0.gaps, Gaps.settings) }),
    Setting(
      "gestures",
      read: { config, value, _ throws(ConfigError) in config.gestures = try Gestures(value) },
      write: { Section.document($0.gestures, Gestures.settings) }),
    Setting(
      "indicators",
      read: { config, value, _ throws(ConfigError) in config.indicators = try Indicators(value) },
      write: { Section.document($0.indicators, Indicators.settings) }),
    Setting(
      "layouts",
      read: { config, value, _ throws(ConfigError) in config.layouts = try Layouts(value) },
      write: { Section.document($0.layouts, Layouts.settings) }),
    Setting(
      "log", read: { config, value, _ throws(ConfigError) in config.log = try Log(value) },
      write: { Section.document($0.log, Log.settings) }),
    Setting(
      "mouse", read: { config, value, _ throws(ConfigError) in config.mouse = try Mouse(value) },
      write: { Section.document($0.mouse, Mouse.settings) }),
    Setting(
      "workspaces",
      read: { config, value, _ throws(ConfigError) in config.workspaces = try Workspaces(value) },
      write: { Section.document($0.workspaces, Workspaces.settings) }),
  ]

  /// `[displays]`, then `[apps]`, whose workspaces are checked against the displays' lists.
  private mutating func readWorkspaceNumbers(
    from document: [String: TOMLValue]
  ) throws(ConfigError) {
    if let value = document["displays"] { displays = try Self.displays(value) }
    if let value = document["apps"] { apps = try Self.apps(value, displays: displays) }
  }
}

extension Config.Gaps {
  fileprivate init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read("gaps", value, into: Self(), Self.settings)
  }

  /// The keys of `[gaps]`, and how each is read.
  static let settings: [Setting<Self>] = [
    Setting(
      "inner",
      read: { gaps, value, name throws(ConfigError) in
        gaps.inner = try Section.points(value, name)
      }, write: { .integer($0.inner) }),
    Setting(
      "outer",
      read: { gaps, value, name throws(ConfigError) in
        gaps.outer = try Section.points(value, name)
      }, write: { .integer($0.outer) }),
  ]
}

extension Config.Gestures {
  fileprivate init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read("gestures", value, into: Self(), Self.settings)
  }

  /// The keys of `[gestures]`, and how each is read.
  static let settings: [Setting<Self>] = [
    Setting(
      "swipe",
      read: { gestures, value, name throws(ConfigError) in
        gestures.swipe = try Section.boolean(value, name)
      }, write: { .boolean($0.swipe) }),
    Setting(
      "fingers",
      read: { gestures, value, name throws(ConfigError) in
        gestures.fingers = try Section.integer(value, name, in: Self.fingersRange)
      }, write: { .integer($0.fingers) }),
    Setting(
      "swipe-distance",
      read: { gestures, value, name throws(ConfigError) in
        gestures.swipeDistance = try Section.number(
          value, name, in: Self.swipeDistanceRange, unit: "trackpad widths")
      }, write: { .float($0.swipeDistance) }),
  ]
}

extension Config.Mouse {
  fileprivate init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read("mouse", value, into: Self(), Self.settings)
  }

  /// The keys of `[mouse]`, and how each is read.
  static let settings: [Setting<Self>] = [
    Setting(
      "follow-interval",
      read: { mouse, value, name throws(ConfigError) in
        mouse.followInterval = try Section.integer(
          value, name, in: Self.followIntervalRange, unit: "milliseconds")
      }, write: { .integer($0.followInterval) }),
    Setting(
      "focus-follows",
      read: { mouse, value, name throws(ConfigError) in
        mouse.focusFollows = try Section.boolean(value, name)
      }, write: { .boolean($0.focusFollows) }),
    Setting(
      "focus-delay",
      read: { mouse, value, name throws(ConfigError) in
        mouse.focusDelay = try Section.integer(
          value, name, in: Self.focusDelayRange, unit: "milliseconds")
      }, write: { .integer($0.focusDelay) }),
    Setting(
      "modifier",
      read: { mouse, value, name throws(ConfigError) in
        guard case .string(let text) = value, let keys = ModifierKeys(parsing: text) else {
          throw .invalid(
            "\(name) must be \"none\" or keys joined by +, from ctrl, option, cmd and shift"
              + " (such as \"option\" or \"ctrl+option\")")
        }
        mouse.modifier = keys
      }, write: { .string($0.modifier.description) }),
    Setting(
      "gap-resize",
      read: { mouse, value, name throws(ConfigError) in
        mouse.gapResize = try Section.boolean(value, name)
      }, write: { .boolean($0.gapResize) }),
  ]
}

extension Config.Workspaces {
  fileprivate init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read("workspaces", value, into: Self(), Self.settings)
  }

  /// The keys of `[workspaces]`, and how each is read.
  static let settings: [Setting<Self>] = [count]

  private static let count = Setting<Self>(
    "count",
    read: { workspaces, value, name throws(ConfigError) in
      workspaces.count = try Section.integer(value, name, in: countRange)
    }, write: { .integer($0.count) })
}

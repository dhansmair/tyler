import Foundation

/// What the map shows on an app's windows instead of the app's icon.
public enum IndicatorIcon: Equatable, Sendable {
  /// An SF Symbol, by name, such as `globe`.
  case symbol(String)
  /// A single character drawn in `Config.Indicator.iconFont`, such as a Nerd Font's Firefox
  /// glyph.
  case glyph(Character)

  /// One character is a glyph; anything longer names an SF Symbol.
  init?(_ text: String) {
    guard !text.isEmpty else { return nil }
    self = text.count == 1 ? .glyph(Character(text)) : .symbol(text)
  }
}

extension Config {
  /// Which menu bar items show.
  public struct Indicator: Equatable, Sendable {
    /// The font glyph icons are drawn in, unless the config file names another.
    public static let defaultIconFont = "Symbols Nerd Font"

    /// The workspace numbers and the layout's symbol, such as `1 [2] 3 4  ▥`.
    public var text: Bool
    /// A thumbnail of every workspace with its windows.
    public var map: Bool
    /// Whether the map shows each window's app icon.
    public var showsIcons: Bool
    /// What to show instead of an app's icon, keyed by bundle ID or app name in lower case.
    public var icons: [String: IndicatorIcon]
    /// The font of glyph icons, by family or PostScript name, such as a Nerd Font.
    public var iconFont: String

    public init(
      text: Bool = true, map: Bool = true, showsIcons: Bool = true,
      icons: [String: IndicatorIcon] = [:],
      iconFont: String = Indicator.defaultIconFont
    ) {
      self.text = text
      self.map = map
      self.showsIcons = showsIcons
      self.icons = icons
      self.iconFont = iconFont
    }

    /// The icon set for this app, if any; matched like `assignedWorkspace`.
    public func icon(bundleID: String?, appName: String) -> IndicatorIcon? {
      Config.lookUp(icons, bundleID: bundleID, appName: appName)
    }
  }
}

extension Config.Indicator {
  init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read(
      "indicator", value, into: Self(),
      Setting("text") { indicator, value, name throws(ConfigError) in
        indicator.text = try Section.boolean(value, name)
      },
      Setting("map") { indicator, value, name throws(ConfigError) in
        indicator.map = try Section.boolean(value, name)
      },
      Setting("show-icons") { indicator, value, name throws(ConfigError) in
        indicator.showsIcons = try Section.boolean(value, name)
      },
      Setting("icon-font") { indicator, value, name throws(ConfigError) in
        guard case .string(let font) = value, !font.isEmpty else {
          throw .invalid("\(name) must be the name of a font, such as \"\(Self.defaultIconFont)\"")
        }
        indicator.iconFont = font
      },
      Setting("icons") { indicator, value, name throws(ConfigError) in
        indicator.icons = try Self.icons(value, name)
      })
  }

  /// `[indicator.icons]`: app (bundle ID or name) = SF Symbol name or glyph.
  private static func icons(
    _ value: TOMLValue, _ name: String
  ) throws(ConfigError) -> [String: IndicatorIcon] {
    guard case .table(let table) = value else {
      throw .invalid(
        "\(name) must be a table: write [\(name)] and put app = \"symbol name\" below it")
    }
    var icons: [String: IndicatorIcon] = [:]
    for (app, value) in table.sorted(by: { $0.key < $1.key }) {
      if case .table = value {
        throw .invalid(
          "\(name).\(app) is a table: quote app names and bundle IDs that contain dots")
      }
      guard case .string(let text) = value, let icon = IndicatorIcon(text) else {
        throw .invalid(
          "\(name).\(app) must be an SF Symbol's name, such as \"globe\", or one glyph, such as \"\\uf269\""
        )
      }
      guard icons.updateValue(icon, forKey: app.lowercased()) == nil else {
        throw .invalid("\(name).\(app) is set twice (app names and bundle IDs ignore case)")
      }
    }
    return icons
  }
}

import Foundation
import TylerCore

extension Config {
  /// The menu bar items, each in its own section.
  package struct Indicators: Equatable, Sendable {
    package var text: Text
    package var map: Map

    package init(text: Text = Text(), map: Map = Map()) {
      self.text = text
      self.map = map
    }
  }
}

extension Config.Indicators {
  /// The workspace numbers and the layout's symbol, such as `1 [2] 3 4  ▥`.
  package struct Text: Equatable, Sendable {
    package var isEnabled: Bool

    package init(isEnabled: Bool = true) {
      self.isEnabled = isEnabled
    }
  }

  /// A thumbnail of every workspace with its windows.
  package struct Map: Equatable, Sendable {
    /// The font glyph icons are drawn in, unless the config file names another.
    package static let defaultIconFont = "Symbols Nerd Font"

    package var isEnabled: Bool
    /// Whether the map shows each window's app icon, or the icon `[apps]` sets for the app.
    package var showsIcons: Bool
    /// The font of glyph icons, by family or PostScript name, such as a Nerd Font.
    package var iconFont: String

    package init(
      isEnabled: Bool = true, showsIcons: Bool = true, iconFont: String = Map.defaultIconFont
    ) {
      self.isEnabled = isEnabled
      self.showsIcons = showsIcons
      self.iconFont = iconFont
    }
  }
}

extension Config.Indicators {
  init(_ value: TOMLValue) throws(ConfigError) {
    self = try Section.read("indicators", value, into: Self(), Self.settings)
  }

  /// The sections of `[indicators]`, one per menu bar item.
  static let settings: [Setting<Self>] = [
    Setting(
      "text",
      read: { indicators, value, name throws(ConfigError) in
        indicators.text = try Section.read(name, value, into: Text(), Text.settings)
      }, write: { Section.document($0.text, Text.settings) }),
    Setting(
      "map",
      read: { indicators, value, name throws(ConfigError) in
        indicators.map = try Section.read(name, value, into: Map(), Map.settings)
      }, write: { Section.document($0.map, Map.settings) }),
  ]
}

extension Config.Indicators.Text {
  /// The keys of `[indicators.text]`, and how each is read.
  static let settings: [Setting<Self>] = [enabled]

  private static let enabled = Setting<Self>(
    "enabled",
    read: { text, value, name throws(ConfigError) in
      text.isEnabled = try Section.boolean(value, name)
    }, write: { .boolean($0.isEnabled) })
}

extension Config.Indicators.Map {
  /// The keys of `[indicators.map]`, and how each is read.
  static let settings: [Setting<Self>] = [
    Setting(
      "enabled",
      read: { map, value, name throws(ConfigError) in
        map.isEnabled = try Section.boolean(value, name)
      }, write: { .boolean($0.isEnabled) }),
    Setting(
      "show-icons",
      read: { map, value, name throws(ConfigError) in
        map.showsIcons = try Section.boolean(value, name)
      }, write: { .boolean($0.showsIcons) }),
    Setting(
      "icon-font",
      read: { map, value, name throws(ConfigError) in
        guard case .string(let font) = value, !font.isEmpty else {
          throw .invalid("\(name) must be the name of a font, such as \"\(Self.defaultIconFont)\"")
        }
        map.iconFont = font
      }, write: { .string($0.iconFont) }),
  ]
}

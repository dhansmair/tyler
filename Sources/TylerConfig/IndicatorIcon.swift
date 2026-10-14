/// What the map shows on an app's windows instead of the app's icon.
package enum IndicatorIcon: Equatable, Sendable {
  /// An SF Symbol, by name, such as `globe`.
  case symbol(String)
  /// A single character drawn in `Config.Indicators.Map.iconFont`, such as a Nerd Font's Firefox
  /// glyph.
  case glyph(Character)

  /// One character is a glyph; anything longer names an SF Symbol.
  init?(_ text: String) {
    guard !text.isEmpty else { return nil }
    self = text.count == 1 ? .glyph(Character(text)) : .symbol(text)
  }

  /// The icon as the config file writes it.
  var text: String {
    switch self {
    case .symbol(let name): name
    case .glyph(let character): String(character)
    }
  }
}

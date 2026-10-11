import Testing

@testable import TylerCore

@Suite("Config: indicator")
struct IndicatorConfigTests {
  @Test func bothIndicatorsShowByDefault() throws {
    #expect(
      try Config.parse("").indicator == Config.Indicator(text: true, map: true, showsIcons: true))
  }

  @Test func iconsUseTheSymbolsNerdFontByDefault() throws {
    #expect(try Config.parse("").indicator.iconFont == "Symbols Nerd Font")
  }

  @Test func parsesTheIndicators() throws {
    let config = try Config.parse(
      """
      [indicator]
      text = false
      map = true
      show-icons = false
      icon-font = "Hack Nerd Font"

      [indicator.icons]
      Firefox = "\\udb80\\ude39"
      "com.mitchellh.ghostty" = "terminal"
      """)
    #expect(
      config.indicator
        == Config.Indicator(
          text: false, map: true, showsIcons: false,
          icons: ["firefox": .glyph("\u{F0239}"), "com.mitchellh.ghostty": .symbol("terminal")],
          iconFont: "Hack Nerd Font"))
    #expect(try Config.parse("indicator.map = false").indicator == Config.Indicator(map: false))
  }

  @Test(arguments: [
    ("globe", IndicatorIcon.symbol("globe")),
    ("doc.text", .symbol("doc.text")),
    ("\u{F0239}", .glyph("\u{F0239}")),
    ("G", .glyph("G")),
    ("e\u{301}", .glyph("e\u{301}")),
  ])
  func oneCharacterIsAGlyphAndMoreASymbolsName(text: String, icon: IndicatorIcon) {
    #expect(IndicatorIcon(text) == icon)
  }

  @Test func anAppsIconIsFoundByBundleIDBeforeName() {
    let indicator = Config.Indicator(
      icons: ["firefox": .symbol("globe"), "org.mozilla.firefox": .glyph("\u{F0239}")])
    #expect(
      indicator.icon(bundleID: "org.mozilla.Firefox", appName: "Firefox") == .glyph("\u{F0239}"))
    #expect(indicator.icon(bundleID: nil, appName: "FIREFOX") == .symbol("globe"))
    #expect(indicator.icon(bundleID: nil, appName: "Ghostty") == nil)
  }

  @Test(arguments: [
    (
      "indicator = true",
      "indicator must be a table: write [indicator] and put text, map, show-icons, icon-font and icons below it"
    ),
    (
      "[indicator]\nmenu = true",
      "unknown setting 'indicator.menu' (use text, map, show-icons, icon-font or icons)"
    ),
    ("[indicator]\nmap = \"no\"", "indicator.map must be true or false"),
    (
      "[indicator]\nicon-font = 3",
      "indicator.icon-font must be the name of a font, such as \"Symbols Nerd Font\""
    ),
    (
      "[indicator]\nicon-font = \"\"",
      "indicator.icon-font must be the name of a font, such as \"Symbols Nerd Font\""
    ),
    (
      "[indicator]\nicons = 3",
      "indicator.icons must be a table: write [indicator.icons] and put app = \"symbol name\" below it"
    ),
    (
      "[indicator.icons]\nFirefox = 3",
      "indicator.icons.Firefox must be an SF Symbol's name, such as \"globe\", or one glyph, such as \"\\uf269\""
    ),
    (
      "[indicator.icons]\nFirefox = \"\"",
      "indicator.icons.Firefox must be an SF Symbol's name, such as \"globe\", or one glyph, such as \"\\uf269\""
    ),
    (
      "[indicator.icons]\nFirefox = \"globe\"\nfirefox = \"flame\"",
      "indicator.icons.firefox is set twice (app names and bundle IDs ignore case)"
    ),
    (
      "[indicator.icons]\ncom.mitchellh.ghostty = \"terminal\"",
      "indicator.icons.com is a table: quote app names and bundle IDs that contain dots"
    ),
  ])
  func rejectsInvalidSettings(text: String, message: String) {
    #expect(throws: ConfigError.invalid(message)) {
      try Config.parse(text)
    }
  }
}

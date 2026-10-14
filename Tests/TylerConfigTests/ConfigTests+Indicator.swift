import Testing
import TylerCore

@testable import TylerConfig

@Suite("Config: indicators")
struct ConfigIndicatorTests {
  @Test func bothIndicatorsShowByDefault() throws {
    let indicators = try Config.parse("").indicators
    #expect(indicators.text.isEnabled && indicators.map.isEnabled && indicators.map.showsIcons)
  }

  @Test func iconsUseTheSymbolsNerdFontByDefault() throws {
    #expect(try Config.parse("").indicators.map.iconFont == "Symbols Nerd Font")
  }

  @Test func parsesTheIndicators() throws {
    let config = try Config.parse(
      """
      [indicators.text]
      enabled = false

      [indicators.map]
      enabled = true
      show-icons = false
      icon-font = "Hack Nerd Font"
      """)
    #expect(
      config.indicators
        == Config.Indicators(
          text: .init(isEnabled: false),
          map: .init(isEnabled: true, showsIcons: false, iconFont: "Hack Nerd Font")))
    #expect(
      try Config.parse("indicators.map.enabled = false").indicators
        == Config.Indicators(map: .init(isEnabled: false)))
  }

  @Test(arguments: [
    (
      "indicators = true",
      "indicators must be a table: write [indicators] and put text and map below it"
    ),
    (
      "[indicator]\nmap = true",
      "unknown setting 'indicator'"
    ),
    (
      "[indicators]\nmenu = true",
      "unknown setting 'indicators.menu' (use text or map)"
    ),
    (
      "[indicators]\ntext = true",
      "indicators.text must be a table: write [indicators.text] and put enabled below it"
    ),
    (
      "[indicators.text]\nshow-icons = true",
      "unknown setting 'indicators.text.show-icons' (use enabled)"
    ),
    ("[indicators.map]\nenabled = \"no\"", "indicators.map.enabled must be true or false"),
    ("[indicators.text]\nenabled = 1", "indicators.text.enabled must be true or false"),
    (
      "[indicators.map]\nicon-font = 3",
      "indicators.map.icon-font must be the name of a font, such as \"Symbols Nerd Font\""
    ),
    (
      "[indicators.map]\nicon-font = \"\"",
      "indicators.map.icon-font must be the name of a font, such as \"Symbols Nerd Font\""
    ),
  ])
  func rejectsInvalidSettings(text: String, message: String) {
    #expect(throws: ConfigError.invalid(message)) {
      try Config.parse(text)
    }
  }
}

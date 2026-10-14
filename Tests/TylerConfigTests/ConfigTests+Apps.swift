import Testing
import TylerCore

@testable import TylerConfig

@Suite("Config: apps")
struct ConfigAppsTests {
  @Test func parsesAnAppsSettingsByNameOrBundleID() throws {
    let config = try Config.parse(
      """
      [workspaces]
      count = 5

      [apps.Firefox]
      workspace = 3
      icon = "\\udb80\\ude39"

      [apps."com.mitchellh.ghostty"]
      workspace = 5
      icon = "terminal"

      [apps.Safari]
      """)
    #expect(
      config.apps == [
        "firefox": Config.App(workspace: 3, icon: .glyph("\u{F0239}")),
        "com.mitchellh.ghostty": Config.App(workspace: 5, icon: .symbol("terminal")),
        "safari": Config.App(),
      ])
    #expect(config.assignedWorkspace(bundleID: "org.mozilla.firefox", appName: "Firefox") == 3)
    #expect(config.assignedWorkspace(bundleID: "COM.mitchellh.Ghostty", appName: "Ghostty") == 5)
    #expect(config.assignedWorkspace(bundleID: nil, appName: "Safari") == nil)
    #expect(config.icon(bundleID: nil, appName: "FIREFOX") == .glyph("\u{F0239}"))
    #expect(config.icon(bundleID: "com.apple.Safari", appName: "Safari") == nil)
  }

  @Test func theBundleIDWinsOverTheAppNameForEachSetting() {
    let config = Config(apps: [
      "firefox": Config.App(workspace: 2, icon: .symbol("globe")),
      "org.mozilla.firefox": Config.App(workspace: 3),
    ])
    #expect(config.assignedWorkspace(bundleID: "org.mozilla.firefox", appName: "Firefox") == 3)
    #expect(
      config.icon(bundleID: "org.mozilla.firefox", appName: "Firefox") == .symbol("globe"),
      "the bundle ID's table sets no icon, so the name's applies")
  }

  @Test func withoutDisplaysAnAppMayNameAnotherDisplaysWorkspace() throws {
    #expect(
      try Config.parse("[apps.Firefox]\nworkspace = 7").apps == [
        "firefox": Config.App(workspace: 7)
      ])
  }

  @Test func withDisplaysAnAppsWorkspaceMayBeAnyListedOne() throws {
    let config = try Config.parse("[displays.3]\nworkspaces = [7]\n[apps.Firefox]\nworkspace = 7")
    #expect(config.apps == ["firefox": Config.App(workspace: 7)])
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

  @Test(arguments: [
    ("apps = 3", "apps must be a table: write [apps.<app>] and put workspace and icon below it"),
    (
      "[apps]\nFirefox = 3",
      "apps.Firefox must be a table: write [apps.Firefox] and put workspace and icon below it"
    ),
    (
      "[apps.Firefox]\nspace = 3",
      "unknown setting 'apps.Firefox.space' (use workspace or icon)"
    ),
    ("[apps.Firefox]\nworkspace = 0", "apps.Firefox.workspace must be a workspace number, 1 to 99"),
    (
      "[apps.Firefox]\nworkspace = 100",
      "apps.Firefox.workspace must be a workspace number, 1 to 99"
    ),
    (
      "[apps.Firefox]\nworkspace = \"3\"",
      "apps.Firefox.workspace must be a workspace number, 1 to 99"
    ),
    (
      "[apps.Firefox]\nworkspace = 7\n[displays.1]\nworkspaces = [1, 2]\n[displays.2]\nworkspaces = [5]",
      "apps.Firefox.workspace = 7, but no display lists workspace 7"
    ),
    (
      "[apps.Firefox]\nicon = 3",
      "apps.Firefox.icon must be an SF Symbol's name, such as \"globe\", or one glyph, such as \"\\uf269\""
    ),
    (
      "[apps.Firefox]\nicon = \"\"",
      "apps.Firefox.icon must be an SF Symbol's name, such as \"globe\", or one glyph, such as \"\\uf269\""
    ),
    (
      "[apps.Firefox]\nworkspace = 3\n[apps.firefox]\nworkspace = 2",
      "apps.firefox is set twice (app names and bundle IDs ignore case)"
    ),
    (
      "[apps.org.mozilla.firefox]\nworkspace = 3",
      "apps.org is a table of tables: quote app names and bundle IDs that contain dots,"
        + " like [apps.\"com.mitchellh.ghostty\"]"
    ),
  ])
  func rejectsInvalidSettings(text: String, message: String) {
    #expect(throws: ConfigError.invalid(message)) {
      try Config.parse(text)
    }
  }
}

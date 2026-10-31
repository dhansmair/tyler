import Foundation
import Testing
import TylerCore

@testable import TylerConfig

/// `Config.document` writes back every setting `parse` reads, so `read` and `write` can't drift.
@Suite("Config: as a document")
struct ConfigDocumentTests {
  private static let everythingChanged = """
    [animations]
    swap = 0
    drag-preview = 300
    retile = 100

    [editor]
    command = "open -na Ghostty --args -e nvim"

    [gaps]
    inner = 8
    outer = 3

    [gestures]
    swipe = false
    fingers = 4
    swipe-distance = 0.55

    [indicators.text]
    enabled = false

    [indicators.map]
    enabled = false
    show-icons = false
    icon-font = "Hack Nerd Font"

    [layouts]
    cycle = ["strip", "tall"]
    default = "full"
    notice = false

    [log]
    level = "debug"

    [mouse]
    follow-interval = 0
    focus-follows = true
    focus-delay = 250
    modifier = "ctrl+option"
    gap-resize = false

    [workspaces]
    count = 6

    [displays.1]
    workspaces = [1, 2, 3]

    [displays.3]
    workspaces = [7]

    [apps.Firefox]
    workspace = 7
    icon = "\\udb80\\ude39"

    [apps."com.mitchellh.ghostty"]
    icon = "terminal"

    [apps.Safari]
    """

  @Test(arguments: ["", everythingChanged])
  func aConfigReadsBackFromItsDocument(text: String) throws {
    let config = try Config.parse(text)
    #expect(try Config.parse(document: config.document) == config)
    #expect(try Config.parse(TOML.write(config.document)) == config)
  }

  @Test func theDocumentChangesWithEverySetting() throws {
    let config = try Config.parse(Self.everythingChanged)
    for name in Config.settingNames where !name.contains("*") {
      let path = name.split(separator: ".").map(String.init)
      #expect(
        Self.value(at: path, in: config.document) != Self.value(at: path, in: Config().document),
        "\(name) is written the same as its default")
    }
  }

  @Test func theDefaultDocumentSetsEverySettingButTheTablesOfAppsAndDisplays() {
    let document = Config().document
    for name in Config.settingNames where !name.contains("*") {
      let path = name.split(separator: ".").map(String.init)
      #expect(Self.value(at: path, in: document) != nil, "\(name) is missing")
    }
    #expect(document["apps"] == nil && document["displays"] == nil)
  }

  private static func value(at path: [String], in table: [String: TOMLValue]) -> TOMLValue? {
    guard let first = path.first, let value = table[first] else { return nil }
    guard path.count > 1 else { return value }
    guard case .table(let inner) = value else { return nil }
    return Self.value(at: Array(path.dropFirst()), in: inner)
  }
}

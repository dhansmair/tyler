import Testing
import TylerCore

@testable import TylerConfig

@Suite("Config: the modifier")
struct ConfigModifierTests {
  @Test(
    arguments: [
      ("option", ModifierKeys.option), ("none", []), ("ctrl+option", [.control, .option]),
      ("option+ctrl", [.control, .option]), ("cmd+shift+ctrl", [.command, .shift, .control]),
    ] as [(String, ModifierKeys)])
  func parsesTheModifier(text: String, keys: ModifierKeys) throws {
    #expect(try Config.parse("[mouse]\nmodifier = \"\(text)\"").mouse.modifier == keys)
  }

  @Test(arguments: ["\"alt\"", "\"option+option\"", "\"\"", "\"option+\"", "\"Option\"", "1"])
  func rejectsAnUnknownModifier(value: String) {
    let message =
      "mouse.modifier must be \"none\" or keys joined by +, from ctrl, option, cmd and shift"
      + " (such as \"option\" or \"ctrl+option\")"
    #expect(throws: ConfigError.invalid(message)) {
      try Config.parse("[mouse]\nmodifier = \(value)")
    }
  }
}

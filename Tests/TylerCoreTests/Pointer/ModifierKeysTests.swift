import Testing

@testable import TylerCore

@Suite("ModifierKeys")
struct ModifierKeysTests {
  @Test(
    arguments: [
      (ModifierKeys.option, "option"), ([], "none"), ([.option, .control], "ctrl+option"),
      ([.shift, .command, .option, .control], "ctrl+option+cmd+shift"),
    ] as [(ModifierKeys, String)])
  func writesTheModifierAsTheConfigDoes(keys: ModifierKeys, text: String) {
    #expect(keys.description == text)
    #expect(ModifierKeys(parsing: text) == keys)
  }
}

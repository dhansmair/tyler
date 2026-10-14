import Testing
import TylerClient

@Suite("ConfigEditing")
struct ConfigEditingTests {
  @Test(arguments: [
    (["VISUAL": "nvim", "EDITOR": "vim"], ConfigEditing.inTerminal(editor: "nvim")),
    (["EDITOR": "vim"], .inTerminal(editor: "vim")),
    (["VISUAL": "", "EDITOR": "code --wait"], .inTerminal(editor: "code --wait")),
    (["VISUAL": "", "EDITOR": ""], .byServer),
    ([:], .byServer),
  ])
  func aTerminalEditsInPlace(environment: [String: String], editing: ConfigEditing) {
    #expect(ConfigEditing.choose(isTerminal: true, environment: environment) == editing)
  }

  @Test func withoutATerminalTylerdOpensTheFile() {
    #expect(ConfigEditing.choose(isTerminal: false, environment: ["EDITOR": "vim"]) == .byServer)
  }
}

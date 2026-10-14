import Testing
import TylerCore

@testable import TylerConfig

@Suite("TOML: writing, and keys and values on their own")
struct TOMLWritingTests {
  @Test(arguments: [
    TOMLValue.integer(-17), .integer(0), .float(0.3), .float(1), .float(1e-5), .boolean(true),
    .boolean(false), .string(""), .string("tall"), .string("say \"hi\"\tnow\\ \n"),
    .string("\u{1}\u{7F}"), .string("\u{F0239}"), .string("e\u{301}"),
    .array([]), .array([.string("tall"), .string("full")]), .array([.integer(1), .integer(2)]),
  ])
  func aWrittenValueReadsBackTheSame(value: TOMLValue) throws {
    #expect(try TOML.parseValue(value.written) == value)
    #expect(try TOML.parse("a = \(value.written)") == ["a": value])
  }

  @Test func valuesAreWrittenAsTheFileWouldHaveThem() {
    #expect(TOMLValue.float(0.3).written == "0.3")
    #expect(TOMLValue.string("tall").written == "\"tall\"")
    #expect(TOMLValue.array([.string("tall"), .string("full")]).written == "[\"tall\", \"full\"]")
    #expect(
      TOMLValue.table(["b": .integer(2), "a": .boolean(true)]).written == "{ a = true, b = 2 }")
  }

  @Test func aDocumentGetsAHeaderPerTableWithValues() throws {
    let document: [String: TOMLValue] = [
      "gaps": .table(["inner": .integer(8), "outer": .integer(3)]),
      "apps": .table([
        "com.mitchellh.ghostty": .table(["icon": .string("terminal")]),
        "safari": .table([:]),
      ]),
    ]
    let text = TOML.write(document)
    #expect(
      text == """
        [apps."com.mitchellh.ghostty"]
        icon = "terminal"

        [apps.safari]

        [gaps]
        inner = 8
        outer = 3
        """)
    #expect(try TOML.parse(text) == document)
  }

  @Test func aTableWrittenAtAPathStartsItsHeadersThere() {
    #expect(
      TOML.write(["inner": .integer(8)], at: ["gaps"]) == "[gaps]\ninner = 8")
    #expect(TOML.write(["inner": .integer(8)]) == "inner = 8")
  }

  @Test(arguments: [
    ("gaps.inner", ["gaps", "inner"]),
    (" gaps . inner ", ["gaps", "inner"]),
    ("apps.\"com.mitchellh.ghostty\".icon", ["apps", "com.mitchellh.ghostty", "icon"]),
    ("apps.'Google Chrome'.workspace", ["apps", "Google Chrome", "workspace"]),
    ("displays.2.workspaces", ["displays", "2", "workspaces"]),
  ])
  func parsesAKeyOnItsOwn(text: String, key: [String]) throws {
    #expect(try TOML.parseKey(text) == key)
  }

  @Test(arguments: ["", "gaps.", "gaps inner", "gaps.inner = 3", "[gaps]"])
  func rejectsWhatIsNotAKey(text: String) {
    #expect(throws: TOMLError.self) { try TOML.parseKey(text) }
  }

  @Test(arguments: ["", "tall", "1 2", "[1", "{ a = 1 }"])
  func rejectsWhatIsNotAValue(text: String) {
    #expect(throws: TOMLError.self) { try TOML.parseValue(text) }
  }
}

import Testing

@testable import TylerCore

@Suite("TOML")
struct TOMLTests {
  @Test(arguments: [
    ("a = 1", TOMLValue.integer(1)),
    ("a = -17", .integer(-17)),
    ("a = +5", .integer(5)),
    ("a = 0", .integer(0)),
    ("a = 1_000", .integer(1000)),
    ("a = 0.5", .float(0.5)),
    ("a = 1e3", .float(1000)),
    ("a = -2.5E-1", .float(-0.25)),
    ("a = true", .boolean(true)),
    ("a = false", .boolean(false)),
    ("a = \"x # y\"", .string("x # y")),
    ("a = \"say \\\"hi\\\"\\tnow\\\\\"", .string("say \"hi\"\tnow\\")),
    ("a = 'C:\\path'", .string("C:\\path")),
    ("a = \"\"", .string("")),
    ("a = \"\\u00e9t\\u00C9\"", .string("étÉ")),
    ("a = \"\\uf269\"", .string("\u{f269}")),
    ("a = \"\\U000F0239\"", .string("\u{F0239}")),
    ("a = \"\\udb80\\ude39\"", .string("\u{F0239}")),
    ("a = \"\\uD83D\\uDE00!\"", .string("\u{1F600}!")),
    ("a=1", .integer(1)),
    ("\ta\t=\t1\t# comment", .integer(1)),
  ])
  func parsesValues(text: String, expected: TOMLValue) throws {
    #expect(try TOML.parse(text) == ["a": expected])
  }

  @Test func parsesTablesDottedKeysAndComments() throws {
    let text = """
      # a comment
      top = 1

      [gaps]
      inner = 8   # trailing comment
      outer.x = 2

      [a.b]
      "quoted key" = 'd'
      """
    let expected: [String: TOMLValue] = [
      "top": .integer(1),
      "gaps": .table(["inner": .integer(8), "outer": .table(["x": .integer(2)])]),
      "a": .table(["b": .table(["quoted key": .string("d")])]),
    ]
    #expect(try TOML.parse(text) == expected)
  }

  @Test func anEmptyTableIsKept() throws {
    #expect(try TOML.parse("[gaps]") == ["gaps": .table([:])])
  }

  @Test(arguments: ["", "\n\n", "# only a comment", "   "])
  func blankDocumentsAreEmpty(text: String) throws {
    #expect(try TOML.parse(text).isEmpty)
  }

  @Test func arraysOnOneLineAreRead() throws {
    let text = """
      a = [1, 2, 3]  # numbers
      b = []
      c = [ "x", 'y', ]
      d = [[1], [2, 3]]
      """
    #expect(
      try TOML.parse(text) == [
        "a": .array([.integer(1), .integer(2), .integer(3)]),
        "b": .array([]),
        "c": .array([.string("x"), .string("y")]),
        "d": .array([.array([.integer(1)]), .array([.integer(2), .integer(3)])]),
      ])
  }

  @Test func windowsLineEndingsWork() throws {
    #expect(try TOML.parse("[t]\r\na = 1\r\n") == ["t": .table(["a": .integer(1)])])
  }

  @Test(arguments: [
    ("a", 1, "expected '=' after the key"),
    ("a =", 1, "expected a value"),
    ("a = # comment", 1, "expected a value"),
    ("= 1", 1, "unexpected '=', expected a key"),
    ("a = 1\na = 2", 2, "'a' is set twice"),
    ("[t]\nb = 1\n[t]", 3, "table [t] is defined twice"),
    ("a = 1\n[a]", 2, "'a' is a value, not a table"),
    ("a = 1\na.b = 2", 2, "'a' is a value, not a table"),
    ("[t\nb = 1", 1, "expected ']' after the table name"),
    ("[t] x", 1, "unexpected 'x'"),
    ("a = 1 2", 1, "unexpected '2'"),
    ("a = [1, 2", 1, "an array must close on the same line"),
    ("a = [1,\n2]", 1, "an array must close on the same line"),
    ("a = [1 2]", 1, "unexpected '2' in an array"),
    ("a = [,]", 1, "expected a value"),
    ("a = { b = 1 }", 1, "inline tables are not supported"),
    ("[[t]]", 1, "arrays of tables ([[...]]) are not supported"),
    ("a = \"open", 1, "unterminated string"),
    ("a = 'open", 1, "unterminated string"),
    ("a = \"\"\"x\"\"\"", 1, "multi-line strings are not supported"),
    ("a = \"\\x\"", 1, "unsupported escape '\\x'"),
    ("a = \"\\u12\"", 1, "\\u needs 4 hex digits"),
    ("a = \"\\u12x4\"", 1, "\\u needs 4 hex digits"),
    ("a = \"\\U0001F60\"", 1, "\\U needs 8 hex digits"),
    ("a = \"\\ud800\"", 1, "\\ud800 is not a Unicode character"),
    ("a = \"\\ude39\"", 1, "\\ude39 is not a Unicode character"),
    ("a = \"\\udb80\\u0041\"", 1, "\\udb80 is not a Unicode character"),
    ("a = \"\\udb80\\ux\"", 1, "\\u needs 4 hex digits"),
    ("a = \"\\U00110000\"", 1, "\\U00110000 is not a Unicode character"),
    ("a = 01", 1, "'01' is not a valid value"),
    ("a = 1__0", 1, "'1__0' is not a valid value"),
    ("a = _1", 1, "'_1' is not a valid value"),
    ("a = 1_", 1, "'1_' is not a valid value"),
    ("a = 1.", 1, "'1.' is not a valid value"),
    ("a = .5", 1, "'.5' is not a valid value"),
    ("a = yes", 1, "'yes' is not a valid value"),
    ("a = 1979-05-27", 1, "'1979-05-27' is not a valid value"),
    ("a = 99999999999999999999", 1, "'99999999999999999999' is too large"),
  ])
  func reportsErrorsWithTheirLine(text: String, line: Int, message: String) {
    #expect(throws: TOMLError(line: line, message: message)) {
      try TOML.parse(text)
    }
  }

  @Test func errorsDescribeTheirLine() {
    #expect(TOMLError(line: 3, message: "boom").description == "line 3: boom")
  }
}

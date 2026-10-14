import TylerCore

/// Parses the subset of TOML that tyler's config needs: comments, `[table]` and `[a.b]`
/// headers, bare, quoted and dotted keys, single-line strings (with `\uXXXX` and `\UXXXXXXXX`
/// escapes), integers, floats, booleans and arrays on one line. Arrays across lines, inline
/// tables, multi-line strings and dates are rejected with an error rather than misread; add them
/// when a setting needs them. Beyond TOML, a `\uXXXX\uXXXX` surrogate pair is read as the character it encodes,
/// the way JSON writes characters past U+FFFF.
package enum TOML {
  package static func parse(_ text: String) throws(TOMLError) -> [String: TOMLValue] {
    var root: [String: TOMLValue] = [:]
    var tablePath: [String] = []
    var headers: Set<[String]> = []
    // Splitting on `isNewline` handles "\r\n", which Swift treats as a single character.
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (offset, rawLine) in lines.enumerated() {
      let number = offset + 1
      var scanner = LineScanner(rawLine, line: number)
      scanner.skipWhitespace()
      if scanner.isAtEndOrComment { continue }
      if scanner.consume("[") {
        if scanner.peek == "[" {
          throw scanner.error("arrays of tables ([[...]]) are not supported")
        }
        let path = try scanner.parseKey()
        scanner.skipWhitespace()
        guard scanner.consume("]") else { throw scanner.error("expected ']' after the table name") }
        try scanner.expectEnd()
        guard headers.insert(path).inserted else {
          throw scanner.error("table [\(path.joined(separator: "."))] is defined twice")
        }
        try makeTable(at: path[...], in: &root, line: number)
        tablePath = path
      } else {
        let key = try scanner.parseKey()
        scanner.skipWhitespace()
        guard scanner.consume("=") else { throw scanner.error("expected '=' after the key") }
        scanner.skipWhitespace()
        let value = try scanner.parseValue()
        try scanner.expectEnd()
        let path = tablePath + key
        try set(value, at: path[...], in: &root, line: number, fullKey: path)
      }
    }
    return root
  }

  /// A key on its own, such as `gaps.inner` or `apps."com.mitchellh.ghostty".icon`, split at the
  /// dots.
  package static func parseKey(_ text: String) throws(TOMLError) -> [String] {
    var scanner = LineScanner(text[...], line: 1)
    scanner.skipWhitespace()
    let key = try scanner.parseKey()
    try scanner.expectEnd()
    return key
  }

  /// A value on its own, such as `5`, `"tall"` or `["tall", "full"]`.
  package static func parseValue(_ text: String) throws(TOMLError) -> TOMLValue {
    var scanner = LineScanner(text[...], line: 1)
    scanner.skipWhitespace()
    let value = try scanner.parseValue()
    try scanner.expectEnd()
    return value
  }

  private static func set(
    _ value: TOMLValue,
    at path: ArraySlice<String>,
    in table: inout [String: TOMLValue],
    line: Int,
    fullKey: [String]
  ) throws(TOMLError) {
    guard let key = path.first else { return }
    guard path.count > 1 else {
      guard table[key] == nil else {
        throw TOMLError(line: line, message: "'\(fullKey.joined(separator: "."))' is set twice")
      }
      table[key] = value
      return
    }
    var child = try existingTable(key, in: table, line: line)
    try set(value, at: path.dropFirst(), in: &child, line: line, fullKey: fullKey)
    table[key] = .table(child)
  }

  private static func makeTable(
    at path: ArraySlice<String>,
    in table: inout [String: TOMLValue],
    line: Int
  ) throws(TOMLError) {
    guard let key = path.first else { return }
    var child = try existingTable(key, in: table, line: line)
    try makeTable(at: path.dropFirst(), in: &child, line: line)
    table[key] = .table(child)
  }

  /// The table stored under `key`, or an empty one if there is none yet.
  private static func existingTable(
    _ key: String,
    in table: [String: TOMLValue],
    line: Int
  ) throws(TOMLError) -> [String: TOMLValue] {
    switch table[key] {
    case nil: return [:]
    case .table(let existing): return existing
    default: throw TOMLError(line: line, message: "'\(key)' is a value, not a table")
    }
  }
}

extension TOML {
  /// Reads one line of TOML, character by character.
  private struct LineScanner {
    private let characters: [Character]
    private var index = 0
    private let line: Int

    init(_ text: Substring, line: Int) {
      characters = Array(text)
      self.line = line
    }

    var peek: Character? { index < characters.count ? characters[index] : nil }

    var isAtEndOrComment: Bool { peek == nil || peek == "#" }

    func error(_ message: String) -> TOMLError {
      TOMLError(line: line, message: message)
    }

    mutating func skipWhitespace() {
      while peek == " " || peek == "\t" { index += 1 }
    }

    mutating func consume(_ character: Character) -> Bool {
      guard peek == character else { return false }
      index += 1
      return true
    }

    /// Only whitespace and a comment may follow.
    mutating func expectEnd() throws(TOMLError) {
      skipWhitespace()
      if let character = peek, character != "#" { throw error("unexpected '\(character)'") }
    }

    // MARK: - Keys

    /// A key such as `inner`, `"quoted key"` or `gaps.inner`, split at the dots.
    mutating func parseKey() throws(TOMLError) -> [String] {
      var parts = [try parseKeyPart()]
      while true {
        let start = index
        skipWhitespace()
        guard consume(".") else {
          index = start
          return parts
        }
        skipWhitespace()
        parts.append(try parseKeyPart())
      }
    }

    private mutating func parseKeyPart() throws(TOMLError) -> String {
      switch peek {
      case "\"":
        return try parseBasicString()
      case "'":
        return try parseLiteralString()
      default:
        var key = ""
        while let character = peek, Self.isBareKeyCharacter(character) {
          key.append(character)
          index += 1
        }
        guard !key.isEmpty else {
          throw error(peek.map { "unexpected '\($0)', expected a key" } ?? "expected a key")
        }
        return key
      }
    }

    private static func isBareKeyCharacter(_ character: Character) -> Bool {
      character.isASCII && (character.isLetter || character.isNumber || "_-".contains(character))
    }

    // MARK: - Values

    mutating func parseValue() throws(TOMLError) -> TOMLValue {
      switch peek {
      case nil, "#", ",", "]":
        throw error("expected a value")
      case "\"":
        return .string(try parseBasicString())
      case "'":
        return .string(try parseLiteralString())
      case "[":
        return .array(try parseArray())
      case "{":
        throw error("inline tables are not supported")
      default:
        return try parseBareValue()
      }
    }

    /// `[a, b, ...]` on one line, with an optional comma after the last value.
    private mutating func parseArray() throws(TOMLError) -> [TOMLValue] {
      index += 1
      var values: [TOMLValue] = []
      while true {
        skipWhitespace()
        if consume("]") { return values }
        guard peek != nil, peek != "#" else { throw error("an array must close on the same line") }
        values.append(try parseValue())
        skipWhitespace()
        if consume("]") { return values }
        guard consume(",") else {
          throw error(
            peek.map { "unexpected '\($0)' in an array" } ?? "an array must close on the same line")
        }
      }
    }

    /// A boolean or a number: everything up to whitespace, a comment, or the end of an array item.
    private mutating func parseBareValue() throws(TOMLError) -> TOMLValue {
      var token = ""
      while let character = peek, !" \t#,]".contains(character) {
        token.append(character)
        index += 1
      }
      switch token {
      case "true": return .boolean(true)
      case "false": return .boolean(false)
      default: return try Self.number(token, line: line)
      }
    }

    private static func number(_ token: String, line: Int) throws(TOMLError) -> TOMLValue {
      let invalid = TOMLError(line: line, message: "'\(token)' is not a valid value")
      // An underscore may only sit between two digits.
      if token.contains(/(^|[^0-9])_|_([^0-9]|$)/) { throw invalid }
      let digits = token.replacing("_", with: "")
      if digits.wholeMatch(of: /[+-]?(0|[1-9][0-9]*)/) != nil {
        guard let integer = Int(digits) else {
          throw TOMLError(line: line, message: "'\(token)' is too large")
        }
        return .integer(integer)
      }
      let isFloat =
        digits.wholeMatch(of: /[+-]?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/) != nil
      guard isFloat, let float = Double(digits) else { throw invalid }
      return .float(float)
    }

    // MARK: - Strings

    /// A `"..."` string with backslash escapes.
    private mutating func parseBasicString() throws(TOMLError) -> String {
      index += 1
      if peek == "\"", index + 1 < characters.count, characters[index + 1] == "\"" {
        throw error("multi-line strings are not supported")
      }
      var result = ""
      while let character = peek {
        index += 1
        switch character {
        case "\"":
          return result
        case "\\":
          result.append(try parseEscape())
        default:
          result.append(character)
        }
      }
      throw error("unterminated string")
    }

    private mutating func parseEscape() throws(TOMLError) -> Character {
      guard let character = peek else { throw error("unterminated string") }
      index += 1
      switch character {
      case "\"": return "\""
      case "\\": return "\\"
      case "n": return "\n"
      case "t": return "\t"
      case "r": return "\r"
      case "u": return try parseUnicodeEscape(digits: 4)
      case "U": return try parseUnicodeEscape(digits: 8)
      default: throw error("unsupported escape '\\\(character)'")
      }
    }

    /// The rest of a `\uXXXX` or `\UXXXXXXXX` escape: exactly `digits` hex digits naming a
    /// Unicode scalar value. A `\u` high surrogate followed by a `\u` low surrogate is read as
    /// the pair's character, as in JSON (the Nerd Fonts cheat sheet gives glyphs that way).
    private mutating func parseUnicodeEscape(digits: Int) throws(TOMLError) -> Character {
      let prefix = digits == 4 ? "\\u" : "\\U"
      let (hex, value) = try parseHex(digits: digits, prefix: prefix)
      if digits == 4, (0xD800...0xDBFF).contains(value), let low = try parseLowSurrogate() {
        let combined = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
        if let scalar = Unicode.Scalar(combined) { return Character(scalar) }
      }
      guard let scalar = Unicode.Scalar(value) else {
        throw error("\(prefix)\(hex) is not a Unicode character")
      }
      return Character(scalar)
    }

    /// A `\uXXXX` low surrogate right here, read if there is one.
    private mutating func parseLowSurrogate() throws(TOMLError) -> UInt32? {
      guard index + 1 < characters.count, characters[index] == "\\", characters[index + 1] == "u"
      else { return nil }
      let start = index
      index += 2
      let (_, value) = try parseHex(digits: 4, prefix: "\\u")
      guard (0xDC00...0xDFFF).contains(value) else {
        index = start
        return nil
      }
      return value
    }

    /// Exactly `digits` hex digits, and their value.
    private mutating func parseHex(
      digits: Int, prefix: String
    ) throws(TOMLError) -> (hex: String, value: UInt32) {
      let end = index + digits
      guard end <= characters.count else { throw error("\(prefix) needs \(digits) hex digits") }
      let hex = String(characters[index..<end])
      guard hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16) else {
        throw error("\(prefix) needs \(digits) hex digits")
      }
      index = end
      return (hex, value)
    }

    /// A `'...'` string, taken literally.
    private mutating func parseLiteralString() throws(TOMLError) -> String {
      index += 1
      if peek == "'", index + 1 < characters.count, characters[index + 1] == "'" {
        throw error("multi-line strings are not supported")
      }
      var result = ""
      while let character = peek {
        index += 1
        if character == "'" { return result }
        result.append(character)
      }
      throw error("unterminated string")
    }
  }
}

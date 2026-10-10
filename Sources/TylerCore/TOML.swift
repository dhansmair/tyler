/// A value in a TOML document.
public enum TOMLValue: Equatable, Sendable {
  case string(String)
  case integer(Int)
  case float(Double)
  case boolean(Bool)
  case table([String: TOMLValue])
}

/// A syntax error in a TOML document, with the 1-based line it was found on.
public struct TOMLError: Error, Equatable, Sendable, CustomStringConvertible {
  public let line: Int
  public let message: String

  public init(line: Int, message: String) {
    self.line = line
    self.message = message
  }

  public var description: String { "line \(line): \(message)" }
}

/// Parses the subset of TOML that tyler's config needs: comments, `[table]` and `[a.b]`
/// headers, bare, quoted and dotted keys, and single-line strings, integers, floats and
/// booleans. Arrays, inline tables, multi-line strings and dates are rejected with an error
/// rather than misread; add them when a setting needs them.
public enum TOML {
  public static func parse(_ text: String) throws(TOMLError) -> [String: TOMLValue] {
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
    case nil, "#":
      throw error("expected a value")
    case "\"":
      return .string(try parseBasicString())
    case "'":
      return .string(try parseLiteralString())
    case "[":
      throw error("arrays are not supported")
    case "{":
      throw error("inline tables are not supported")
    default:
      return try parseBareValue()
    }
  }

  /// A boolean or a number: everything up to whitespace or a comment.
  private mutating func parseBareValue() throws(TOMLError) -> TOMLValue {
    var token = ""
    while let character = peek, character != " ", character != "\t", character != "#" {
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
    let isFloat = digits.wholeMatch(of: /[+-]?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/) != nil
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
    default: throw error("unsupported escape '\\\(character)'")
    }
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

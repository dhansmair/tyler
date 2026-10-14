import TylerCore

/// Writing values and tables back out as TOML that `TOML.parse` reads.
extension TOMLValue {
  /// The value as it follows `key = `: `5`, `0.3`, `"tall"`, `["tall", "full"]`. A table comes
  /// out inline, `{ a = 1 }`, which `TOML.parse` doesn't read; `TOML.write` gives tables headers.
  package var written: String {
    switch self {
    case .string(let text): TOML.quoted(text)
    case .integer(let number): String(number)
    case .float(let number): String(number)
    case .boolean(let isOn): String(isOn)
    case .array(let values): "[" + values.map(\.written).joined(separator: ", ") + "]"
    case .table(let table):
      table.isEmpty
        ? "{}"
        : "{ "
          + table.sorted { $0.key < $1.key }.map { "\(TOML.key($0.key)) = \($0.value.written)" }
          .joined(separator: ", ") + " }"
    }
  }
}

extension TOML {
  /// `table` as a document: its values as `key = value` lines, then each table under its
  /// `[header]`, which starts with `path`. Keys are sorted, so the output is stable.
  package static func write(_ table: [String: TOMLValue], at path: [String] = []) -> String {
    var sections: [String] = []
    let values = table.filter { !$0.value.isTable }.sorted { $0.key < $1.key }
    let tables = table.compactMap { key, value in value.tableValue.map { (key, $0) } }
      .sorted { $0.0 < $1.0 }
    let lines = values.map { "\(key($0.key)) = \($0.value.written)" }
    // A table with values, or nothing at all, needs its header; one holding only tables doesn't.
    if !path.isEmpty, !lines.isEmpty || tables.isEmpty {
      sections.append(
        (["[" + path.map(key).joined(separator: ".") + "]"] + lines).joined(separator: "\n"))
    } else if !lines.isEmpty {
      sections.append(lines.joined(separator: "\n"))
    }
    for (name, child) in tables {
      sections.append(write(child, at: path + [name]))
    }
    return sections.joined(separator: "\n\n")
  }

  /// A key part, bare when it can be and quoted otherwise.
  static func key(_ part: String) -> String {
    let isBare =
      !part.isEmpty
      && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_-".contains($0)) }
    return isBare ? part : quoted(part)
  }

  /// A basic string, with the escapes `TOML.parse` reads.
  static func quoted(_ text: String) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": result += "\\\""
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\t": result += "\\t"
      case "\r": result += "\\r"
      case _ where scalar.value < 0x20 || scalar.value == 0x7F:
        let hex = String(scalar.value, radix: 16, uppercase: true)
        result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result + "\""
  }
}

extension TOMLValue {
  var isTable: Bool { tableValue != nil }

  var tableValue: [String: TOMLValue]? {
    if case .table(let table) = self { table } else { nil }
  }
}

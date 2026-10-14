import Foundation

/// Wire format: one JSON document per line, terminated by `\n`.
package enum Wire {
  /// The byte that ends every message: `\n`.
  package static let terminator: UInt8 = 0x0A

  package static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(value)
    data.append(terminator)
    return data
  }

  package static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
    try JSONDecoder().decode(type, from: line)
  }
}

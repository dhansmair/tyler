import Foundation

/// A command sent from the `mwm` client to the `mwmd` server.
public enum Request: Codable, Equatable, Sendable {
  case ping
  case list
}

/// The server's reply to a `Request`.
public enum Response: Codable, Equatable, Sendable {
  case pong
  case windows([WindowInfo])
  case error(String)
}

/// Wire format: one JSON document per line, terminated by `\n`.
public enum Wire {
  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(value)
    data.append(0x0A)
    return data
  }

  public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
    try JSONDecoder().decode(type, from: line)
  }
}

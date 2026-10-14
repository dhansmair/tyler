/// The system-wide window number (`CGWindowID`), stable for the lifetime of a window.
package struct WindowID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
  package let rawValue: UInt32

  package init(_ rawValue: UInt32) {
    self.rawValue = rawValue
  }

  package init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(UInt32.self)
  }

  package func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  package static func < (lhs: WindowID, rhs: WindowID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  package var description: String { String(rawValue) }
}

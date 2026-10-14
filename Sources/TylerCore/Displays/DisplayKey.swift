/// Names a display across unplugging, sleep and restarts: macOS gives each display a UUID that
/// stays the same, while its `CGDirectDisplayID` may change after a reboot.
package struct DisplayKey: Hashable, Codable, Sendable, CustomStringConvertible {
  package var rawValue: String

  package init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  package var description: String { rawValue }
}

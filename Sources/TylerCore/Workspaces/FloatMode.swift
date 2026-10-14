/// Whether the focused window floats: `on` floats it, `off` tiles it again.
package enum FloatMode: String, Codable, CaseIterable, Sendable {
  case on
  case off
  case toggle
}

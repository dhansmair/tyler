/// A position in the tiling list, relative to the focused window.
package enum ListTarget: String, Codable, CaseIterable, Sendable {
  case next
  case prev
  /// The first window in the list. Users type (and the wire format carries) `master`, the
  /// xmonad term; the Swift name is `main` because SwiftLint's inclusive_language rule rejects
  /// `master` in identifiers.
  case main = "master"
}

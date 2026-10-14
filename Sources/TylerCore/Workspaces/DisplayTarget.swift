/// Which display a display command goes to.
package enum DisplayTarget: Codable, Equatable, Sendable {
  /// The display before the focused one in tyler's numbering, wrapping from the first to the last.
  case prev
  /// The display after the focused one in tyler's numbering, wrapping from the last to the first.
  case next
  /// A display by its number: 1 is the primary, the others follow left to right, then top to
  /// bottom.
  case number(Int)
}

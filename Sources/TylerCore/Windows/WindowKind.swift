/// What sort of window this is, derived from its Accessibility role and subrole.
package enum WindowKind: String, Codable, Sendable {
  case standard
  case dialog
  case floating
  case other

  /// Maps raw Accessibility strings to a kind. Unknown or missing values are `.other`.
  package static func classify(role: String?, subrole: String?) -> WindowKind {
    switch (role, subrole) {
    case ("AXSheet", _), (_, "AXDialog"), (_, "AXSystemDialog"):
      return .dialog
    case (_, "AXFloatingWindow"), (_, "AXSystemFloatingWindow"):
      return .floating
    case ("AXWindow", "AXStandardWindow"):
      return .standard
    default:
      return .other
    }
  }
}

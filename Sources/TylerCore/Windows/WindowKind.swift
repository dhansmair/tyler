/// What sort of window this is, derived from its Accessibility role, subrole and title bar.
package enum WindowKind: String, Codable, Sendable {
  case standard
  case dialog
  case floating
  case other

  /// Maps raw Accessibility strings to a kind. Unknown or missing values are `.other`. The
  /// subrole alone misleads both ways (measured on macOS 26.7, `macos-behaviour.md`): TextEdit's
  /// untitled documents are `AXDialog` until the app is first active, and its Open panel is an
  /// `AXStandardWindow` without a close or minimize button. A dialog never offers full screen,
  /// and a window you can neither close nor minimize isn't a document.
  package static func classify(
    role: String?, subrole: String?, buttons: WindowButtons
  ) -> WindowKind {
    switch (role, subrole) {
    case ("AXWindow", "AXDialog") where buttons.contains(.fullScreen):
      return .standard
    case ("AXWindow", "AXStandardWindow") where buttons.isDisjoint(with: [.close, .minimize]):
      return .dialog
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

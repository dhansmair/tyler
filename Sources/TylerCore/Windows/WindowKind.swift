/// What sort of window this is, derived from its Accessibility role, subrole and title bar.
package enum WindowKind: String, Codable, Sendable {
  case standard
  case dialog
  case floating
  case other

  /// Maps raw Accessibility strings to a kind. Unknown or missing values are `.other`. The
  /// subrole alone misleads both ways (measured on macOS 26.7, `macos-behaviour.md`): TextEdit's
  /// untitled documents are `AXDialog` until the app is first active, while its Open panel and
  /// Outlook's reminder popup are `AXStandardWindow`s. A dialog never offers full screen; a
  /// window you can neither close nor minimize, or one without full screen that can't be
  /// resized, isn't a document. Some documents only zoom, so no full screen alone isn't enough.
  /// `isResizable` is `nil` when it wasn't read.
  package static func classify(
    role: String?, subrole: String?, buttons: WindowButtons, isResizable: Bool?
  ) -> WindowKind {
    switch (role, subrole) {
    case ("AXWindow", "AXDialog") where buttons.contains(.fullScreen):
      return .standard
    case ("AXWindow", "AXStandardWindow") where buttons.isDisjoint(with: [.close, .minimize]):
      return .dialog
    case _
    where isResizable == false
      && dependsOnResizability(role: role, subrole: subrole, buttons: buttons):
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

  /// Whether `classify` needs `isResizable`, which costs a second round trip to the app.
  package static func dependsOnResizability(
    role: String?, subrole: String?, buttons: WindowButtons
  ) -> Bool {
    role == "AXWindow" && subrole == "AXStandardWindow" && !buttons.contains(.fullScreen)
      && !buttons.isDisjoint(with: [.close, .minimize])
  }
}

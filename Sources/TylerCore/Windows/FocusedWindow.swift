/// A window that held the focus. `kind` stays known after it closes, and is `nil` if tylerd hadn't
/// heard of the window.
package struct FocusedWindow: Equatable, Sendable {
  package let id: WindowID
  package var kind: WindowKind?

  package init(id: WindowID, kind: WindowKind?) {
    self.id = id
    self.kind = kind
  }

  /// Whether macOS chose the next window because this one went away. A dialog is different:
  /// closing one and focusing another window is what its app meant to do.
  package func leftTheChoiceToMacOS(isGone: Bool) -> Bool {
    kind == .standard && isGone
  }
}

/// A window that held the focus. `kind` stays known after it closes, and is `nil` if tylerd hadn't
/// heard of the window.
package struct FocusedWindow: Equatable, Sendable {
  package let id: WindowID
  package var kind: WindowKind?

  package init(id: WindowID, kind: WindowKind?) {
    self.id = id
    self.kind = kind
  }
}

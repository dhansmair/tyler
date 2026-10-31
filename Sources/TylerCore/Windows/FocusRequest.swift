/// A window tylerd asked macOS to focus a moment ago. `isSecondTry` says it had already asked for
/// that window just before.
package struct FocusRequest: Equatable, Sendable {
  package let window: WindowID
  package let isSecondTry: Bool

  package init(window: WindowID, isSecondTry: Bool) {
    self.window = window
    self.isSecondTry = isSecondTry
  }
}

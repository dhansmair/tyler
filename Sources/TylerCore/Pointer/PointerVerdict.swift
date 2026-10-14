/// What tylerd decided about the window at a point.
package enum PointerVerdict: Codable, Equatable, Sendable {
  case window(WindowID)
  case refused(PointerRefusal)

  /// The window, if it wasn't refused.
  package var window: WindowID? {
    if case .window(let windowID) = self { windowID } else { nil }
  }
}

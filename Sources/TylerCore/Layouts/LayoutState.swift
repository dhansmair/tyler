/// `init()` is a new workspace's state. A state that keeps something per window updates it when
/// a window leaves the list or arrives from another workspace; the others needn't.
package protocol LayoutState: Codable, Equatable, Sendable {
  init()

  /// `windows` is the list the window leaves, still holding it.
  mutating func remove(_ windowID: WindowID, from windows: [WindowID])

  /// `windowID` arrived from a workspace whose state was `other`.
  mutating func adopt(_ windowID: WindowID, from other: Self)
}

extension LayoutState {
  package mutating func remove(_ windowID: WindowID, from windows: [WindowID]) {}
  package mutating func adopt(_ windowID: WindowID, from other: Self) {}
}

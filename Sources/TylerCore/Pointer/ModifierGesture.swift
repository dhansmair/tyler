import CoreGraphics

/// Tells a click from a drag for the presses tyler may take over, and decides which mouse events
/// tyler swallows. Pure: the mouse button interceptor feeds it every press, drag and release,
/// swallows what it says, and acts on what it returns.
///
/// A press made with exactly the modifier keys, over a window tyler may move, is held back; so is
/// a left press with no keys in the gap between two tiled windows, when `takesGaps`. If the
/// pointer then moves `dragThreshold` points, the gesture is tyler's: a move (left button with
/// the modifier), a resize (right) or a gap's divider moved. If the button comes up first, it was
/// a click, and the interceptor posts the held press and the release again so the app still gets
/// it. Once a press is held, every event until its button comes up is swallowed, including the
/// other button's, so the app never sees half a gesture.
package struct ModifierGesture: Sendable {
  /// How far the pointer moves before a held press becomes a drag, in points.
  package static let dragThreshold: CGFloat = 4

  package enum Kind: Equatable, Sendable {
    case move, resize
    /// A drag in the gap between two tiled windows, moving the divider between them.
    case gap
  }

  /// What the interceptor does with an event.
  package enum Verdict: Equatable, Sendable {
    /// Let the event through to the app.
    case pass
    /// Swallow it: the gesture is tyler's.
    case swallow
  }

  /// What the gesture asks of tyler.
  package enum Action: Equatable, Sendable {
    /// A drag began at `start`: move or resize the window there.
    case began(Kind, start: CGPoint)
    /// The pointer is now at this location.
    case moved(CGPoint)
    /// The drag ended at this location.
    case ended(CGPoint)
    /// The held press was a click: post it and its release again.
    case replayClick
  }

  private enum State: Equatable, Sendable {
    case idle
    case held(MouseButton, Kind, start: CGPoint)
    case dragging(MouseButton, last: CGPoint)
  }

  /// The keys that start a gesture; empty turns gestures off.
  package var modifier: ModifierKeys
  /// Whether a left press with no keys may start a gesture in a gap.
  package var takesGaps: Bool
  private var state = State.idle

  package init(modifier: ModifierKeys, takesGaps: Bool = false) {
    self.modifier = modifier
    self.takesGaps = takesGaps
  }

  /// Whether a press is held or a drag is under way.
  package var isActive: Bool { state != .idle }

  /// A button went down with `keys` held. `canCapture` says whether the press is over what a
  /// gesture of that kind takes: a window tyler may move or resize, or a gap. It is asked only
  /// when the keys and the button could start one.
  package mutating func pressed(
    _ button: MouseButton, at location: CGPoint, keys: ModifierKeys,
    canCapture: (Kind) -> Bool
  ) -> Verdict {
    guard state == .idle else { return .swallow }
    guard let kind = kind(of: button, keys: keys), canCapture(kind) else { return .pass }
    state = .held(button, kind, start: location)
    return .swallow
  }

  private func kind(of button: MouseButton, keys: ModifierKeys) -> Kind? {
    if !modifier.isEmpty, keys == modifier { return button == .left ? .move : .resize }
    if takesGaps, keys.isEmpty, button == .left { return .gap }
    return nil
  }

  /// The pointer moved with `button` down.
  package mutating func dragged(
    _ button: MouseButton, to location: CGPoint
  ) -> (Verdict, [Action]) {
    switch state {
    case .idle:
      return (.pass, [])
    case .held(let held, let kind, let start):
      guard button == held, hypot(location.x - start.x, location.y - start.y) >= Self.dragThreshold
      else { return (.swallow, []) }
      state = .dragging(held, last: location)
      return (.swallow, [.began(kind, start: start), .moved(location)])
    case .dragging(let held, _):
      guard button == held else { return (.swallow, []) }
      state = .dragging(held, last: location)
      return (.swallow, [.moved(location)])
    }
  }

  /// `button` came up.
  package mutating func released(
    _ button: MouseButton, at location: CGPoint
  ) -> (Verdict, [Action]) {
    switch state {
    case .idle:
      return (.pass, [])
    case .held(let held, _, _):
      guard button == held else { return (.swallow, []) }
      state = .idle
      return (.swallow, [.replayClick])
    case .dragging(let held, _):
      guard button == held else { return (.swallow, []) }
      state = .idle
      return (.swallow, [.ended(location)])
    }
  }

  /// macOS turned the tap off for being slow, and let the events meanwhile through to the app. A
  /// held press is dropped (the app got its release already); a drag ends where it last was.
  package mutating func tapTurnedOff() -> [Action] {
    defer { state = .idle }
    guard case .dragging(_, let last) = state else { return [] }
    return [.ended(last)]
  }
}

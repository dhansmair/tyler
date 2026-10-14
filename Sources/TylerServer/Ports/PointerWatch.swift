import TylerCore

/// What the pointer reports besides the primary button's drags and releases, which it always
/// reports.
package struct PointerWatch: Equatable, Sendable {
  /// Sideways swipes with this many fingers, as `.swipe` events; `nil` watches no swipes.
  package var swipeFingers: Int?
  /// Movement with no button down, as `.moved` events. Off unless asked, so tylerd isn't woken by
  /// every move when nothing needs them.
  package var moves = false
  /// Presses made with exactly these keys are taken over (`[]` takes none): a drag becomes
  /// `.modifierDragBegan` and what follows, a click goes on to the app.
  package var modifierKeys: ModifierKeys = []
  /// Left presses with no keys in the gap between two tiled windows are taken over too: a drag
  /// becomes `.modifierDragBegan(.gap, …)`, a click goes on to the app.
  package var gapPresses = false

  package init(
    swipeFingers: Int? = nil, moves: Bool = false, modifierKeys: ModifierKeys = [],
    gapPresses: Bool = false
  ) {
    self.swipeFingers = swipeFingers
    self.moves = moves
    self.modifierKeys = modifierKeys
    self.gapPresses = gapPresses
  }
}

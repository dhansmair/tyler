/// Decides when the active event tap that takes over presses has to exist: only while a press
/// may be tyler's. macOS can stop all input when a process loses Accessibility with an active tap
/// in place (see "Events and taps" in `devdocs/macos-behaviour.md`), so it isn't kept the rest of
/// the time.
///
/// A press may be tyler's while exactly the modifier keys are held, while the pointer is over a
/// gap a press would grab, and until the button of a gesture under way comes up.
package struct PressTakeover: Equatable, Sendable {
  package let modifier: ModifierKeys
  package let takesGaps: Bool
  private var keysHeld: ModifierKeys = []
  private var isOverGap = false
  private var isGestureActive = false

  package init(modifier: ModifierKeys, takesGaps: Bool) {
    self.modifier = modifier
    self.takesGaps = takesGaps
  }

  package var needsTap: Bool {
    isGestureActive || (!modifier.isEmpty && keysHeld == modifier) || (takesGaps && isOverGap)
  }

  /// Returns whether `needsTap` changed.
  package mutating func keysChanged(to keys: ModifierKeys) -> Bool {
    changing { $0.keysHeld = keys }
  }

  /// Returns whether `needsTap` changed.
  package mutating func gapHovered(_ isOverGap: Bool) -> Bool {
    changing { $0.isOverGap = isOverGap }
  }

  /// Returns whether `needsTap` changed.
  package mutating func gestureChanged(isActive: Bool) -> Bool {
    changing { $0.isGestureActive = isActive }
  }

  private mutating func changing(_ change: (inout Self) -> Void) -> Bool {
    let before = needsTap
    change(&self)
    return needsTap != before
  }
}

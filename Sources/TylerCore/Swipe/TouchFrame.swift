import Foundation

/// The fingers on the trackpad at one moment: positions are normalized to the trackpad (0 to 1
/// on each axis, x growing to the right). Platform code converts touch events to this, so the
/// recognizer stays free of AppKit.
package struct TouchFrame: Equatable, Sendable {
  /// Seconds, from any fixed origin.
  package let time: TimeInterval
  package let positions: [CGPoint]

  package init(time: TimeInterval, positions: [CGPoint]) {
    self.time = time
    self.positions = positions
  }
}

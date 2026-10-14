/// What a horizontal swipe did. Offsets and velocities are in trackpad widths: an offset of 0.25
/// means the fingers moved a quarter of the trackpad to the right since the swipe began (negative
/// is to the left). Knows nothing about what the swipe moves; that is up to whoever listens.
package enum SwipeUpdate: Equatable, Sendable {
  case began
  case moved(offset: Double)
  /// The fingers lifted (or more joined). `velocity` is in trackpad widths per second over the
  /// last moments of the swipe.
  case ended(velocity: Double)
}

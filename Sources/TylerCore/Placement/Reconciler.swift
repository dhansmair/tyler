import CoreGraphics

/// The moves that bring windows from where they are to where the model wants them: only those
/// more than a point away, since each move is a round trip to the app, and apps round frames.
package enum Reconciler {
  /// `frame` gives where a window is now; a window without one is moved.
  package static func moves(
    toward desired: [Placement], from frame: (WindowID) -> CGRect?
  ) -> [Placement] {
    desired.filter { placement in
      guard let current = frame(placement.id) else { return true }
      return !current.isClose(to: placement.frame)
    }
  }
}

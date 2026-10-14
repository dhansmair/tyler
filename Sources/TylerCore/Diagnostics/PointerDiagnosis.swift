import CoreGraphics

/// tylerd's view of one point on screen, for `tyler debug at`: what it sees there and what it
/// would do, with the reason when it would do nothing.
package struct PointerDiagnosis: Codable, Equatable, Sendable {
  /// The topmost window at the point, as tylerd sees it (without the Dock's window).
  package struct OnTop: Codable, Equatable, Sendable {
    package var id: WindowID
    package var layer: Int
    /// From the registry; `nil` for a window tylerd doesn't track.
    package var appName: String?
    /// The window server's name for its owner, which names a window tylerd doesn't track.
    package var owner: String?
    package var title: String?
    /// The workspace that tiles it, if any.
    package var workspace: Int?

    package init(id: WindowID, layer: Int) {
      self.id = id
      self.layer = layer
    }
  }

  package var point: CGPoint
  /// tyler's number of the display whose frame holds the point.
  package var displayNumber: Int?
  package var visibleFrame: CGRect?
  package var onTop: OnTop?
  /// What moves the windows besides tiling: idle, sliding, swiping or dragging.
  package var interaction = "idle"
  /// `mouse.modifier`, as the config writes it.
  package var modifier = ""
  /// What the decisions were made from.
  package var check: PointerCheck

  package init(point: CGPoint, check: PointerCheck) {
    self.point = point
    self.check = check
  }

  /// Whether a press with the modifier would grab the window on top.
  package var grab: PointerVerdict { check.grab }
  /// Whether focus follows the mouse to the window on top once the pointer rests there.
  package var focus: PointerVerdict { check.focus }
}

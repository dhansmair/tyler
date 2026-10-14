import CoreGraphics

/// Where the pointer was last seen, and the gap the resize cursor shows over, if any. Tells the
/// cursor only what changes, since it is asked again with every pointer move and every layout
/// change.
@MainActor
final class GapHover {
  private let cursor: any GapCursor
  private(set) var location: CGPoint?
  private(set) var shown: CGRect?

  init(cursor: any GapCursor) {
    self.cursor = cursor
  }

  func pointerMoved(to location: CGPoint) {
    self.location = location
  }

  /// Shows the resize cursor over `area`, or hides it for `nil`.
  func show(over area: CGRect?) {
    guard area != shown else { return }
    shown = area
    if let area { cursor.show(over: area) } else { cursor.hide() }
  }
}

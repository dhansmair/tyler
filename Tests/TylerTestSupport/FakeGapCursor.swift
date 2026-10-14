import CoreGraphics

@testable import TylerServer

/// A `GapCursor` that remembers where it shows.
@MainActor
package final class FakeGapCursor: GapCursor {
  /// The gap it shows over, or `nil` while hidden.
  package private(set) var area: CGRect?
  /// How many times it was shown or moved, and hidden.
  package private(set) var showCount = 0
  package private(set) var hideCount = 0

  package init() {}

  package func show(over area: CGRect) {
    self.area = area
    showCount += 1
  }

  package func hide() {
    area = nil
    hideCount += 1
  }
}

import CoreGraphics

@testable import TylerServer

/// A `LayoutNotice` that remembers what it showed.
@MainActor
package final class FakeLayoutNotice: LayoutNotice {
  package private(set) var shown: [(name: String, area: CGRect)] = []

  package init() {}

  package func show(_ name: String, in area: CGRect) {
    shown.append((name, area))
  }
}

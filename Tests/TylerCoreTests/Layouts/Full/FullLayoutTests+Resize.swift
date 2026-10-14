import CoreGraphics
import Testing

@testable import TylerCore

@Suite("Full layout: resizing with the mouse")
struct FullLayoutResizeTests {
  @Test func fullDoesNotFollowTheMouse() {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let updated = FullLayout().state(
      afterResizing: 0, to: CGRect(x: 0, y: 0, width: 600, height: 600), count: 2, in: area)
    #expect(updated == nil)
  }
}

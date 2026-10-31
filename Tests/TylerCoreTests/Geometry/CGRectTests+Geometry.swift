import CoreGraphics
import Testing

@testable import TylerCore

@Suite("CGRect geometry")
struct CGRectGeometryTests {
  private static let slot = CGRect(x: 1022, y: -674, width: 1230, height: 671)

  struct Case: Sendable {
    let current: CGRect
    let expected: CGPoint?
  }

  /// Where a window goes before it is resized into the bottom right slot of a display, which
  /// macOS won't shrink it into as asked while it reaches past the display's bottom edge.
  @Test(
    arguments: [
      // Past the bottom (a terminal rounded up, or clamped 63 points onto the display below):
      // up until its bottom edge is the slot's.
      Case(
        current: CGRect(x: 1022, y: -674, width: 1230, height: 737),
        expected: CGPoint(x: 1022, y: -740)),
      Case(
        current: CGRect(x: 1022, y: -563, width: 1230, height: 640),
        expected: CGPoint(x: 1022, y: -643)),
      // Past the right edge: left until its right edge is the slot's.
      Case(
        current: CGRect(x: 1022, y: -674, width: 1300, height: 671),
        expected: CGPoint(x: 952, y: -674)),
      Case(
        current: CGRect(x: 1022, y: -674, width: 1300, height: 737),
        expected: CGPoint(x: 952, y: -740)),
      // Within the slot's bottom and right edges, give or take a point: it stays.
      Case(current: slot, expected: nil),
      Case(current: CGRect(x: 1022, y: -674, width: 1231, height: 672), expected: nil),
      Case(current: CGRect(x: 1022, y: -900, width: 1000, height: 800), expected: nil),
      Case(current: CGRect(x: 500, y: -1000, width: 600, height: 300), expected: nil),
    ])
  func movesAWindowThatReachesPastTheSlotWithinItsEdges(_ test: Case) {
    #expect(Self.slot.clearingOrigin(from: test.current) == test.expected)
  }

  @Test func rectsWithinAPointAreClose() {
    let rect = CGRect(x: 10, y: 10, width: 100, height: 100)
    #expect(rect.isClose(to: CGRect(x: 11, y: 9, width: 101, height: 99)))
    #expect(!rect.isClose(to: CGRect(x: 12, y: 10, width: 100, height: 100)))
  }

  @Test func onlyASizeChangeOfMoreThanAPointCounts() {
    let rect = CGRect(x: 10, y: 10, width: 100, height: 100)
    #expect(!rect.hasOtherSize(than: CGRect(x: 500, y: 500, width: 101, height: 100)))
    #expect(rect.hasOtherSize(than: CGRect(x: 10, y: 10, width: 102, height: 100)))
  }

  /// Going to another display it doesn't reach past anything there, as in `macos-behaviour.md`.
  @Test func aWindowElsewhereNeedsNoClearing() {
    let farBelow = CGRect(x: 0, y: 5000, width: 3000, height: 3000)
    #expect(Self.slot.clearingOrigin(from: farBelow) == nil)
  }
}

import CoreGraphics
import Testing

@testable import TylerCore

@Suite("FullLayout")
struct FullLayoutTests {
  private let area = CGRect(x: 55, y: 38, width: 1745, height: 1131)

  @Test func everyWindowGetsTheWholeArea() {
    let result = FullLayout().frames(count: 3, in: area)
    #expect(result == Array(repeating: area, count: 3))
  }

  @Test func noWindowsGiveNoFrames() {
    #expect(FullLayout().frames(count: 0, in: area).isEmpty)
  }

  @Test func outerGapApplies() {
    let result = FullLayout().frames(
      count: 1, in: CGRect(x: 0, y: 0, width: 100, height: 100),
      gaps: LayoutGaps(outer: 5))
    #expect(result == [CGRect(x: 5, y: 5, width: 90, height: 90)])
  }
}

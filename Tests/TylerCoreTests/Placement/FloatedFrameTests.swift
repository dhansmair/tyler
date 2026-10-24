import CoreGraphics
import Testing

@testable import TylerCore

@Suite("Floated frame")
struct FloatedFrameTests {
  private static let area = CGRect(x: 0, y: 0, width: 1440, height: 900)

  @Test(arguments: [
    (CGRect(x: 720, y: 0, width: 720, height: 900), CGRect(x: 690, y: 60, width: 720, height: 780)),
    (CGRect(x: 0, y: 0, width: 720, height: 900), CGRect(x: 30, y: 60, width: 720, height: 780)),
    (CGRect(x: 0, y: 0, width: 1440, height: 450), CGRect(x: 60, y: 30, width: 1320, height: 450)),
  ])
  func aWindowShrinksOnlyAlongTheAxisItSpans(slot: CGRect, floated: CGRect) {
    #expect(FloatedFrame.frame(leaving: slot, in: Self.area) == floated)
  }

  @Test func theOnlyWindowShrinksOnEverySide() {
    let floated = FloatedFrame.frame(leaving: Self.area, in: Self.area)
    #expect(floated == CGRect(x: 60, y: 60, width: 1320, height: 780))
  }

  @Test(arguments: [
    (CGRect(x: 720, y: 0, width: 720, height: 450), CGRect(x: 690, y: 30, width: 720, height: 450)),
    (
      CGRect(x: 720, y: 450, width: 720, height: 450),
      CGRect(x: 690, y: 420, width: 720, height: 450)
    ),
  ])
  func aWindowThatSpansNeitherAxisOnlyMovesTowardTheMiddle(slot: CGRect, floated: CGRect) {
    #expect(FloatedFrame.frame(leaving: slot, in: Self.area) == floated)
  }

  @Test(arguments: [
    CGRect(x: 720, y: 0, width: 720, height: 900),
    CGRect(x: 0, y: 450, width: 720, height: 450),
    CGRect(x: 0, y: 0, width: 1440, height: 900),
  ])
  func noEdgeStaysOnTheSlotsEdge(slot: CGRect) {
    let floated = FloatedFrame.frame(leaving: slot, in: Self.area)
    #expect(floated.minX != slot.minX && floated.maxX != slot.maxX)
    #expect(floated.minY != slot.minY && floated.maxY != slot.maxY)
  }

  @Test func aShortSpanShrinksOnlyToTheMinimum() {
    let area = CGRect(x: 0, y: 0, width: 1440, height: 250)
    let floated = FloatedFrame.frame(leaving: area, in: area)
    #expect(floated == CGRect(x: 60, y: 25, width: 1320, height: 200))
  }

  @Test func theWindowStaysInsideTheArea() {
    let slot = CGRect(x: 1060, y: 0, width: 400, height: 450)
    let floated = FloatedFrame.frame(leaving: slot, in: Self.area)
    #expect(floated == CGRect(x: 1030, y: 30, width: 400, height: 450))
    let pastTheEdge = CGRect(x: 1100, y: 0, width: 400, height: 450)
    #expect(FloatedFrame.frame(leaving: pastTheEdge, in: Self.area).maxX == Self.area.maxX)
  }
}

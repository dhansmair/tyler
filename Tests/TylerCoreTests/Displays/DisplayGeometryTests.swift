import CoreGraphics
import Testing

@testable import TylerCore

@Suite("DisplayGeometry")
struct DisplayGeometryTests {
  // A primary display of 1800x1169, with a second 1920x1080 display to its right.
  private let primary = DisplayInfo(
    id: 1,
    frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 55, y: 38, width: 1745, height: 1131)
  )
  private let secondary = DisplayInfo(
    id: 2,
    frame: CGRect(x: 1800, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 1800, y: 0, width: 1920, height: 1080)
  )

  @Test func flipsAppKitRectToAXCoordinates() {
    // AppKit: the full primary screen has origin (0, 0). In AX coordinates it's the same.
    let full = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    #expect(DisplayGeometry.axRect(fromAppKit: full, primaryScreenHeight: 1169) == full)
  }

  @Test func flipsARectAtTheTopOfTheScreen() {
    // A 100pt-tall strip at the top of a 1000pt screen: AppKit y=900, AX y=0.
    let strip = CGRect(x: 0, y: 900, width: 500, height: 100)
    let flipped = DisplayGeometry.axRect(fromAppKit: strip, primaryScreenHeight: 1000)
    #expect(flipped == CGRect(x: 0, y: 0, width: 500, height: 100))
  }

  @Test func flipsADisplayAboveThePrimaryToNegativeY() {
    // A display sitting above the primary has AppKit y >= primary height, so AX y < 0.
    let above = CGRect(x: 0, y: 1000, width: 800, height: 600)
    let flipped = DisplayGeometry.axRect(fromAppKit: above, primaryScreenHeight: 1000)
    #expect(flipped == CGRect(x: 0, y: -600, width: 800, height: 600))
  }

  @Test func flippingTwiceIsTheIdentity() {
    let rect = CGRect(x: 12, y: 345, width: 67, height: 89)
    let once = DisplayGeometry.axRect(fromAppKit: rect, primaryScreenHeight: 1169)
    #expect(DisplayGeometry.axRect(fromAppKit: once, primaryScreenHeight: 1169) == rect)
  }

  @Test func picksTheDisplayContainingTheWindow() {
    let onPrimary = CGRect(x: 100, y: 100, width: 400, height: 300)
    let onSecondary = CGRect(x: 2000, y: 100, width: 400, height: 300)
    #expect(DisplayGeometry.display(containing: onPrimary, in: [primary, secondary])?.id == 1)
    #expect(DisplayGeometry.display(containing: onSecondary, in: [primary, secondary])?.id == 2)
  }

  @Test func aStraddlingWindowBelongsToTheDisplayItOverlapsMost() {
    // 300pt on the primary, 100pt on the secondary.
    let straddling = CGRect(x: 1500, y: 100, width: 400, height: 300)
    #expect(DisplayGeometry.display(containing: straddling, in: [primary, secondary])?.id == 1)
    // 100pt on the primary, 300pt on the secondary.
    let other = CGRect(x: 1700, y: 100, width: 400, height: 300)
    #expect(DisplayGeometry.display(containing: other, in: [primary, secondary])?.id == 2)
  }

  @Test func anOffScreenWindowBelongsToTheNearestDisplay() {
    let parked = CGRect(x: 5000, y: 500, width: 400, height: 300)
    #expect(DisplayGeometry.display(containing: parked, in: [primary, secondary])?.id == 2)
    let farLeft = CGRect(x: -3000, y: 500, width: 400, height: 300)
    #expect(DisplayGeometry.display(containing: farLeft, in: [primary, secondary])?.id == 1)
  }

  @Test func noDisplaysMeansNoAnswer() {
    #expect(DisplayGeometry.display(containing: .zero, in: []) == nil)
  }

  @Test func appKitRectUndoesAxRect() {
    let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
    let flipped = DisplayGeometry.axRect(fromAppKit: rect, primaryScreenHeight: 1000)
    #expect(DisplayGeometry.appKitRect(fromAX: flipped, primaryScreenHeight: 1000) == rect)
  }
}

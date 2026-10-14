import CoreGraphics
import Testing

@testable import TylerCore

@Suite("FrameWrite")
struct FrameWriteTests {
  private let current = CGRect(x: 100, y: 0, width: 400, height: 600)

  @Test func aGrowingWindowMovesFirst() {
    let target = CGRect(x: 50, y: 0, width: 450, height: 600)
    #expect(
      FrameWrite.inPassing(from: current, to: target)
        == [.position(target.origin), .size(target.size)])
  }

  @Test func aShrinkingWindowIsResizedFirst() {
    let target = CGRect(x: 150, y: 0, width: 350, height: 600)
    #expect(
      FrameWrite.inPassing(from: current, to: target)
        == [.size(target.size), .position(target.origin)])
  }

  @Test func onlyWhatChangesIsWritten() {
    #expect(
      FrameWrite.inPassing(from: current, to: current.offsetBy(dx: 10, dy: 0))
        == [.position(CGPoint(x: 110, y: 0))])
    #expect(
      FrameWrite.inPassing(from: current, to: CGRect(x: 100, y: 0, width: 300, height: 600))
        == [.size(CGSize(width: 300, height: 600))])
    #expect(FrameWrite.inPassing(from: current, to: current) == [])
  }

  @Test func growingOneWayAndShrinkingTheOtherHasNoSafeOrder() {
    #expect(
      FrameWrite.inPassing(from: current, to: CGRect(x: 100, y: 0, width: 500, height: 500)) == nil)
  }
}

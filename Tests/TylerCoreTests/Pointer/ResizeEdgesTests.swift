import CoreGraphics
import Testing

@testable import TylerCore

@Suite("ResizeEdges")
struct ResizeEdgesTests {
  static let frame = CGRect(x: 100, y: 100, width: 400, height: 300)

  @Test(
    arguments: [
      (CGPoint(x: 110, y: 110), ResizeEdges([.left, .top])),
      (CGPoint(x: 490, y: 110), ResizeEdges([.right, .top])),
      (CGPoint(x: 110, y: 390), ResizeEdges([.left, .bottom])),
      (CGPoint(x: 490, y: 390), ResizeEdges([.right, .bottom])),
      (CGPoint(x: 300, y: 250), ResizeEdges([.right, .bottom])),
    ] as [(CGPoint, ResizeEdges)])
  func picksTheEdgesOfTheGrabbedQuarter(point: CGPoint, edges: ResizeEdges) {
    #expect(ResizeEdges(grabbedAt: point, in: Self.frame) == edges)
  }

  struct ResizeCase: Sendable {
    let edges: ResizeEdges
    let delta: CGVector
    let expected: CGRect
  }

  @Test(arguments: [
    ResizeCase(
      edges: [.right, .bottom], delta: CGVector(dx: 50, dy: -20),
      expected: CGRect(x: 100, y: 100, width: 450, height: 280)),
    ResizeCase(
      edges: [.left, .top], delta: CGVector(dx: 50, dy: -20),
      expected: CGRect(x: 150, y: 80, width: 350, height: 320)),
    ResizeCase(
      edges: [.left, .bottom], delta: CGVector(dx: -30, dy: 10),
      expected: CGRect(x: 70, y: 100, width: 430, height: 310)),
    ResizeCase(
      edges: [.right, .bottom], delta: CGVector(dx: -1000, dy: -1000),
      expected: CGRect(x: 100, y: 100, width: 50, height: 50)),
    ResizeCase(
      edges: [.left, .top], delta: CGVector(dx: 1000, dy: 1000),
      expected: CGRect(x: 450, y: 350, width: 50, height: 50)),
  ])
  func movesOnlyTheGrabbedEdges(_ test: ResizeCase) {
    #expect(Self.frame.resizing(test.edges, by: test.delta) == test.expected)
  }

  @Test func neverGrowsARectSmallerThanTheMinimum() {
    let small = CGRect(x: 0, y: 0, width: 30, height: 20)
    #expect(
      small.resizing(ResizeEdges([.right, .bottom]), by: CGVector(dx: -100, dy: -100)) == small)
  }
}

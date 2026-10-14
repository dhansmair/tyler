import CoreGraphics
import Testing

@testable import TylerCore

/// Tall with a gap of 10 in a 1000 × 1000 area: window 1 on the left, window 2 above window 3 on
/// the right.
@Suite("GapGrab")
struct GapGrabTests {
  static let tall = [
    Placement(id: WindowID(1), frame: CGRect(x: 0, y: 0, width: 495, height: 1000)),
    Placement(id: WindowID(2), frame: CGRect(x: 505, y: 0, width: 495, height: 495)),
    Placement(id: WindowID(3), frame: CGRect(x: 505, y: 505, width: 495, height: 495)),
  ]

  /// The gap beside window 1, along its whole height.
  static let besideMain = GapGrab(
    windowID: WindowID(1), edge: .right, area: CGRect(x: 495, y: 0, width: 10, height: 1000))

  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let point: CGPoint
    let grab: GapGrab?

    var testDescription: String { name }
  }

  @Test(arguments: [
    Case(
      name: "the gap beside the main window moves its right edge", point: CGPoint(x: 500, y: 200),
      grab: Self.besideMain),
    Case(
      name: "the gap beside the main window lower down too", point: CGPoint(x: 497, y: 900),
      grab: Self.besideMain),
    Case(
      name: "the gap between the stacked windows moves the upper one's bottom edge",
      point: CGPoint(x: 700, y: 500),
      grab: GapGrab(
        windowID: WindowID(2), edge: .bottom,
        area: CGRect(x: 505, y: 495, width: 495, height: 10))),
    Case(name: "inside a window", point: CGPoint(x: 200, y: 200), grab: nil),
    Case(name: "on a window's edge", point: CGPoint(x: 505, y: 200), grab: nil),
    Case(name: "where the gaps meet", point: CGPoint(x: 500, y: 500), grab: nil),
    Case(name: "outside the tiled area", point: CGPoint(x: 1005, y: 200), grab: nil),
  ])
  func findsTheGapAndTheEdgeFacingIt(_ test: Case) {
    #expect(GapGrab(at: test.point, among: Self.tall) == test.grab)
  }

  @Test func windowsWithoutAGapHaveNone() {
    let slots = [
      Placement(id: WindowID(1), frame: CGRect(x: 0, y: 0, width: 500, height: 1000)),
      Placement(id: WindowID(2), frame: CGRect(x: 500, y: 0, width: 500, height: 1000)),
    ]
    #expect(GapGrab(at: CGPoint(x: 500, y: 200), among: slots) == nil)
  }

  @Test func aSingleWindowHasNoGap() {
    let slots = [Placement(id: WindowID(1), frame: CGRect(x: 10, y: 10, width: 980, height: 980))]
    #expect(GapGrab(at: CGPoint(x: 5, y: 200), among: slots) == nil)
  }

  /// Three columns: the gap belongs to the window just before it, not the first one.
  @Test func picksTheNearestWindowBeforeTheGap() {
    let slots = [
      Placement(id: WindowID(1), frame: CGRect(x: 0, y: 0, width: 300, height: 1000)),
      Placement(id: WindowID(2), frame: CGRect(x: 310, y: 0, width: 300, height: 1000)),
      Placement(id: WindowID(3), frame: CGRect(x: 620, y: 0, width: 380, height: 1000)),
    ]
    #expect(
      GapGrab(at: CGPoint(x: 615, y: 500), among: slots)
        == GapGrab(
          windowID: WindowID(2), edge: .right, area: CGRect(x: 610, y: 0, width: 10, height: 1000)
        ))
  }

  /// A grid whose columns split at different heights: beside the gap between windows 3 and 4,
  /// windows 1 and 5 reach that height, but window 3 lies between them, so it isn't a gap
  /// between columns.
  @Test func aGapBetweenRowsIsNotTakenForOneBetweenColumns() {
    let slots = [
      Placement(id: WindowID(1), frame: CGRect(x: 0, y: 0, width: 330, height: 620)),
      Placement(id: WindowID(2), frame: CGRect(x: 0, y: 630, width: 330, height: 370)),
      Placement(id: WindowID(3), frame: CGRect(x: 340, y: 0, width: 320, height: 560)),
      Placement(id: WindowID(4), frame: CGRect(x: 340, y: 570, width: 320, height: 430)),
      Placement(id: WindowID(5), frame: CGRect(x: 670, y: 0, width: 330, height: 660)),
      Placement(id: WindowID(6), frame: CGRect(x: 670, y: 670, width: 330, height: 330)),
    ]
    #expect(
      GapGrab(at: CGPoint(x: 500, y: 565), among: slots)
        == GapGrab(
          windowID: WindowID(3), edge: .bottom, area: CGRect(x: 340, y: 560, width: 320, height: 10)
        ))
  }
}

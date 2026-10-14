import CoreGraphics
import Testing

@testable import TylerCore

/// Windows 11, 13 and 21 are in view (on the current workspaces, or floated); window 12 is parked,
/// window 99 is one tylerd doesn't know. Window 11 has focus.
@Suite("PointerFocus")
struct PointerFocusTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    var topmost: UInt32?
    var layer = PointerFocus.normalLayer
    var isMenuOpen = false
    var focused: UInt32? = 11
    let expected: UInt32?

    var testDescription: String { name }
  }

  @Test(arguments: [
    Case(name: "a window in view", topmost: 21, expected: 21),
    Case(name: "a parked window's sliver", topmost: 12, expected: nil),
    Case(name: "an unknown window", topmost: 99, expected: nil),
    Case(name: "nothing under the pointer", topmost: nil, expected: nil),
    Case(name: "a menu or the Dock", topmost: 21, layer: 101, expected: nil),
    Case(name: "with a menu open elsewhere", topmost: 21, isMenuOpen: true, expected: nil),
    Case(name: "the focused window", topmost: 11, expected: nil),
    Case(name: "with nothing focused", topmost: 11, focused: nil, expected: 11),
  ])
  func focusFollowsOnlyToAWindowInView(_ test: Case) {
    let target = PointerFocus.target(
      under: test.topmost.map { StackedWindow(id: WindowID($0), layer: test.layer) },
      isMenuOpen: test.isMenuOpen, inView: Set(ids(11, 13, 21)),
      focusedID: test.focused.map(WindowID.init))
    #expect(target == test.expected.map(WindowID.init))
  }

  private static let displays = [
    CGRect(x: 0, y: 0, width: 1800, height: 1169),
    CGRect(x: -305, y: -1440, width: 2560, height: 1440),
  ]

  @Test(arguments: [
    (20, CGRect(x: 0, y: 0, width: 1800, height: 1169), true),  // the Dock's
    (21, CGRect(x: -305, y: -1440, width: 2560, height: 1440), true),  // Notification Centre's
    (0, CGRect(x: 0, y: 0, width: 1800, height: 1169), false),  // a normal window as large
    (25, CGRect(x: 1657, y: 0, width: 145, height: 39), false),  // a status item
    (21, CGRect(x: 0, y: 0, width: 1800, height: 1168), false),  // not the whole display
    (2_147_483_630, CGRect(x: 541, y: 819, width: 28, height: 40), true),  // the shared cursor
    (2_147_483_631, CGRect(x: 842, y: -1410, width: 267, height: 32), true),  // above the cursor
    (2_147_483_629, CGRect(x: 541, y: 819, width: 28, height: 40), false),  // just below it
  ])
  func overlaysCoverADisplayOrSitAtTheCursor(layer: Int, frame: CGRect, isOverlay: Bool) {
    #expect(
      PointerFocus.isOverlay(layer: layer, frame: frame, displayFrames: Self.displays) == isOverlay)
  }
}

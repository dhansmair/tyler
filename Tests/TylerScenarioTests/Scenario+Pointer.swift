import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// What the user does with the mouse and the trackpad.
extension Scenario {
  /// Where the fingers move in a swipe. Moving them left brings in the next workspace, as on a
  /// page.
  enum Fingers {
    case left
    case right
  }

  /// The user drags `window` by its title bar until the pointer is in the middle of `region` of
  /// display `number`, and lets go. The app moves the window along, keeping its size, as apps do.
  func drag(_ window: UInt32, to region: Region, display number: Int = 1) async {
    guard let frame = frame(of: window) else {
      Issue.record("no window \(window)")
      return
    }
    let target = rect(region, display: number)
    let start = CGPoint(x: frame.midX, y: frame.minY + 10)
    let end = CGPoint(x: target.midX, y: target.midY)
    pointer.isPrimaryButtonDown = true
    await harness.windowSystem.userMoves(
      window, to: frame.offsetBy(dx: end.x - start.x, dy: end.y - start.y))
    await dragPointer(to: end)
    await release(at: end)
  }

  /// The user presses on `window`'s title bar and starts dragging it: its app moves it to `frame`
  /// and reports it. The button stays down until `release(at:)`.
  func pickUp(_ window: UInt32, to frame: CGRect) async {
    pointer.isPrimaryButtonDown = true
    await moveByHand(window, to: frame)
  }

  /// The user drags the pointer to `point`, the button still down.
  func dragPointer(to point: CGPoint) async {
    pointer.drag(to: point)
    await runUntilQuiet()
  }

  /// The user lets go of the button at `point`.
  func release(at point: CGPoint) async {
    pointer.release(at: point)
    await runUntilQuiet()
  }

  /// The user moves the pointer to `point`, with no button down.
  func movePointer(to point: CGPoint) async {
    pointer.move(to: point)
    await runUntilQuiet()
  }

  /// The user moves the pointer to the gap at `point`, presses there, drags it by `offset` and
  /// lets go. Returns whether tylerd took the press; if not, it went to whatever is there.
  @discardableResult
  func dragGap(at point: CGPoint, by offset: CGVector) async -> Bool {
    await movePointer(to: point)
    guard pointer.beginGrab(.gap, at: point) else { return false }
    let end = CGPoint(x: point.x + offset.dx, y: point.y + offset.dy)
    pointer.moveGrab(to: end)
    await runUntilQuiet()
    pointer.endGrab(at: end)
    await runUntilQuiet()
    return true
  }

  /// A swipe on the trackpad across 0.18 of its width, the fingers lifted at rest: past halfway
  /// with the default `swipe-distance`.
  func swipe(_ fingers: Fingers) async {
    let offset = fingers == .left ? -0.18 : 0.18
    for update: SwipeUpdate in [.began, .moved(offset: offset), .ended(velocity: 0)] {
      pointer.swipe(update)
    }
    await runUntilQuiet()
  }

  /// The user moves or resizes `window` by hand to `frame`; its app reports the new frame.
  func moveByHand(_ window: UInt32, to frame: CGRect) async {
    await harness.windowSystem.userMoves(window, to: frame)
    await runUntilQuiet()
  }
}

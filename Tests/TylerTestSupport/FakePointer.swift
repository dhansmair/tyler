import CoreGraphics
import TylerCore

@testable import TylerServer

/// A scriptable `PointerInput`: tests hold the button down and release it.
@MainActor
package final class FakePointer: PointerInput {
  package let events: AsyncStream<PointerEvent>
  private let continuation: AsyncStream<PointerEvent>.Continuation
  package var isPrimaryButtonDown = false
  package private(set) var startCount = 0
  package private(set) var stopCount = 0

  package init() {
    (events, continuation) = AsyncStream.makeStream(of: PointerEvent.self)
  }

  /// The finger count of the swipes being watched for; `nil` when none are.
  package private(set) var swipeFingers: Int?

  package func start() { startCount += 1 }
  package func stop() { stopCount += 1 }

  package func watch(_ watch: PointerWatch) {
    swipeFingers = watch.swipeFingers
    watchesMoves = watch.moves
    modifierKeys = watch.modifierKeys
    takesGaps = watch.gapPresses
  }

  /// Whether the pointer is over a gap a press would grab, as tylerd last said.
  package private(set) var isOverGap = false

  package func gapHovered(_ isOverGap: Bool) { self.isOverGap = isOverGap }

  package var listeners: [InputListener] = []

  /// Whether moves are reported, as `watch` last set it.
  package private(set) var watchesMoves = false

  /// Moves the pointer with no button down. Like the real input, reports it only while moves
  /// are watched.
  package func move(to location: CGPoint) {
    self.location = location
    if watchesMoves { continuation.yield(.moved(location: location)) }
  }

  /// Lets go of the button, as the user would at the end of a drag.
  package func release(at location: CGPoint = .zero) {
    isPrimaryButtonDown = false
    continuation.yield(.primaryButtonReleased(location: location))
  }

  /// Moves the pointer with the button down.
  package func drag(to location: CGPoint) {
    isPrimaryButtonDown = true
    continuation.yield(.primaryButtonDragged(location: location))
  }

  /// The keys presses are taken over with, as `watch` last set them.
  package private(set) var modifierKeys: ModifierKeys = []
  /// Whether presses in a gap are taken over, as `watch` last set it.
  package private(set) var takesGaps = false
  package var canCapture: (@MainActor (CGPoint, ModifierGesture.Kind) -> Bool)?

  /// Whether a press with the modifier at `location` would be taken over, as the interceptor asks.
  package func wouldGrab(at location: CGPoint) -> Bool {
    wouldCapture(.move, at: location)
  }

  /// Whether a press that starts a gesture of `kind` at `location` would be taken over: one with
  /// the modifier, or a press with no keys in a gap.
  package func wouldCapture(_ kind: ModifierGesture.Kind, at location: CGPoint) -> Bool {
    let isWatched = kind == .gap ? takesGaps : !modifierKeys.isEmpty
    return isWatched && canCapture?(location, kind) == true
  }

  /// A press at `start` that the pointer then drags, as the interceptor reports it: nothing
  /// unless `wouldCapture(_:at:)`, and for a gap unless tylerd said the pointer is over one (the
  /// interceptor only exists then). Returns whether it was taken over.
  @discardableResult
  package func beginGrab(_ kind: ModifierGesture.Kind, at start: CGPoint) -> Bool {
    guard kind != .gap || isOverGap, wouldCapture(kind, at: start) else { return false }
    continuation.yield(.modifierDragBegan(kind, location: start))
    return true
  }

  package func moveGrab(to location: CGPoint) {
    continuation.yield(.modifierDragMoved(location: location))
  }

  package func endGrab(at location: CGPoint) {
    continuation.yield(.modifierDragEnded(location: location))
  }

  /// Where the pointer rests during a swipe: on `FakeDisplays.main` unless a test moves it.
  package var location = CGPoint(x: 900, y: 600)

  /// A step of a swipe on the trackpad, with the pointer at `location`.
  package func swipe(_ update: SwipeUpdate) {
    continuation.yield(.swipe(update, location: location))
  }
}

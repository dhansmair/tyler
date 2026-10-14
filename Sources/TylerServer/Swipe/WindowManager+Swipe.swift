import CoreGraphics
import TylerCore

/// A trackpad swipe in progress: its pacing, and how it ends early. `SwipeController` decides how
/// it begins and ends, `SwipeSession` each step.
extension WindowManager {
  /// A swipe acts on the display under the pointer (`location`), which becomes the focused
  /// display.
  func apply(_ update: SwipeUpdate, at location: CGPoint) {
    switch update {
    case .began: beginSwipe(at: location)
    case .moved(let travel): moveSwipe(to: travel)
    case .ended(let velocity): endSwipe(velocity: velocity)
    }
  }

  var swipingWindows: Set<WindowID> { swipe?.session.windows ?? [] }

  private func beginSwipe(at location: CGPoint) {
    endSlideOrSwipe()
    let (session, effects) = SwipeController(context: context).begin(at: location, model: &model)
    run(effects)
    if let session { swipe = Swipe(session: session) }
  }

  /// Moving every window is a round trip to its app each, and swipes report faster than slow
  /// apps move, so the windows are placed at most once a frame: offsets arriving in between
  /// replace each other.
  private func moveSwipe(to travel: Double) {
    guard swipe != nil else { return }
    swipe?.session.move(travel: travel, distance: config.gestures.swipeDistance)
    swipe?.isPlaced = false
    if swipe?.throttle.isHolding == false { placeSwipe() }
  }

  /// Places the windows for the newest offset, holding further steps back until a frame after
  /// this one began.
  private func placeSwipe() {
    guard let current = swipe, !current.isPlaced else {
      swipe?.throttle.release()
      return
    }
    swipe?.isPlaced = true
    guard let step = swipe?.session.step() else { return }
    mover.frameStarted()
    swipe?.throttle.hold(for: animator.frameInterval, on: clock) { [weak self] in
      self?.placeSwipe()
    }
    run([.place(step.placements), .nudge(step.nudges)])
  }

  private func endSwipe(velocity: Double) {
    guard let session = swipe?.session else { return }
    forgetSwipe()
    run(SwipeController(context: context).end(session, velocity: velocity, model: &model))
  }

  /// Ends a swipe early, every window back where it was when the swipe began.
  func abandonSwipe() {
    guard let session = swipe?.session else { return }
    forgetSwipe()
    place(session.abandon())
  }

  /// Forgets the swipe, and any step of it still waiting, leaving the windows where they are.
  func forgetSwipe() {
    swipe?.throttle.release()
    swipe = nil
  }
}

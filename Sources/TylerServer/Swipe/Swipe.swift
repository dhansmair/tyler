import TylerCore

/// A trackpad swipe in progress: what it decides (`SwipeSession`) and its pacing.
struct Swipe {
  var session: SwipeSession
  /// Whether the session's offset has been applied to the windows yet.
  var isPlaced = true
  /// Places the windows at most once a frame.
  var throttle = Throttle()
}

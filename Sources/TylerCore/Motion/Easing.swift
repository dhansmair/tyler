package enum Easing {
  /// No easing: the progress itself, clamped to 0...1.
  package static func linear(_ progress: Double) -> Double {
    progress.clamped(to: 0...1)
  }

  /// Cubic ease-out: starts at full speed and slows to a stop, for finishing a motion that was
  /// already moving (a released swipe).
  package static func easeOut(_ progress: Double) -> Double {
    let rest = 1 - progress.clamped(to: 0...1)
    return 1 - rest * rest * rest
  }

  /// Cubic ease-in-out: slow at both ends, symmetric around the midpoint.
  package static func easeInOut(_ progress: Double) -> Double {
    let clamped = progress.clamped(to: 0...1)
    if clamped < 0.5 { return 4 * clamped * clamped * clamped }
    let rest = -2 * clamped + 2
    return 1 - rest * rest * rest / 2
  }
}

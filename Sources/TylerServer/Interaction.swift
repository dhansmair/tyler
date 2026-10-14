import TylerCore

/// What is moving the windows besides tiling: a slide, a trackpad swipe or a mouse drag. At most one
/// runs at a time, and the enum makes any other state impossible to write: a command or a slide
/// ends a drag, a swipe ends a slide, and a swipe never starts during a drag.
enum Interaction {
  case idle
  case sliding(Slide)
  case swiping(Swipe)
  case dragging(Drag)

  /// The kind, for `tyler debug at`.
  var name: String {
    switch self {
    case .idle: "idle"
    case .sliding: "sliding"
    case .swiping: "swiping"
    case .dragging: "dragging"
    }
  }

  var isIdle: Bool {
    if case .idle = self { true } else { false }
  }

  /// Whether a mouse drag may start or go on: not while a slide or a swipe moves the windows.
  var allowsDrag: Bool {
    switch self {
    case .idle, .dragging: true
    case .sliding, .swiping: false
    }
  }
}

/// Each kind of interaction seen on its own, so code that deals with one reads and changes it
/// directly (`drag?.pendingFrame = …`). Setting one replaces whatever ran before; setting `nil` ends it
/// only if it is the one running. Callers end the running interaction first (`endInteraction`),
/// so replacing one is a bug, and logged.
extension WindowManager {
  var slide: Slide? {
    get {
      if case .sliding(let running) = interaction { running } else { nil }
    }
    set { setInteraction(newValue.map(Interaction.sliding), wasRunning: slide != nil) }
  }

  var swipe: Swipe? {
    get {
      if case .swiping(let session) = interaction { session } else { nil }
    }
    set { setInteraction(newValue.map(Interaction.swiping), wasRunning: swipe != nil) }
  }

  var drag: Drag? {
    get {
      if case .dragging(let drag) = interaction { drag } else { nil }
    }
    set { setInteraction(newValue.map(Interaction.dragging), wasRunning: drag != nil) }
  }

  /// Sets one kind of interaction, or ends it (`nil`). `wasRunning` is whether that kind was
  /// running before; if it wasn't, it may only start from idle.
  private func setInteraction(_ new: Interaction?, wasRunning: Bool) {
    guard let new else {
      if wasRunning {
        logMotionCost()
        interaction = .idle
      }
      return
    }
    if !wasRunning {
      if !interaction.isIdle {
        Self.log.error("interaction started - while another was still running")
        logMotionCost()
      }
      mover.startMeasuring()
    }
    interaction = new
  }

  /// One line per slide, swipe or drag that moved windows: how smooth it could be, and what
  /// held it up.
  private func logMotionCost() {
    guard let cost = mover.stopMeasuring(), cost.writes > 0 else { return }
    let kind =
      switch interaction {
      case .idle: "interaction"
      case .sliding: "slide"
      case .swiping: "swipe"
      case .dragging: "drag"
      }
    Self.log.info("\(kind) finished - \(cost.summary(naming: named))")
  }
}

/// How an interaction ends, in one place, so no caller has to know which kinds there are.
extension WindowManager {
  /// Ends a slide or a swipe, letting a drag go on: a slide jumps to its end, a swipe's windows
  /// go back where they started.
  func endSlideOrSwipe() {
    abandonSwipe()
    finishSlide()
  }

  /// Ends whatever moves the windows besides tiling: a slide, a swipe or a drag.
  func endInteraction() {
    endSlideOrSwipe()
    endDrag()
  }
}

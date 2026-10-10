import TylerCore

/// What is moving the windows besides tiling: a slide, a trackpad pan or a mouse drag. At most one
/// runs at a time, and the enum makes any other state impossible to write: a command or a slide
/// ends a drag, a pan ends a slide, and a pan never starts during a drag.
enum Interaction {
  case idle
  case sliding(WindowManager.RunningAnimation)
  case panning(PanSession)
  case dragging(MouseDrag)

  var isIdle: Bool {
    if case .idle = self { true } else { false }
  }

  /// Whether a mouse drag may start or go on: not while a slide or a pan moves the windows.
  var allowsDrag: Bool {
    switch self {
    case .idle, .dragging: true
    case .sliding, .panning: false
    }
  }
}

/// Each kind of interaction seen on its own, so code that deals with one reads and changes it
/// directly (`pan?.offset = …`). Setting one replaces whatever ran before; setting `nil` ends it
/// only if it is the one running. Callers end the running interaction properly (`finishAnimation`,
/// `endDrag`, `forgetPan`) before starting another, so replacing one is a bug, and logged.
extension WindowManager {
  var animation: RunningAnimation? {
    get {
      if case .sliding(let running) = interaction { running } else { nil }
    }
    set { setInteraction(newValue.map(Interaction.sliding), wasRunning: animation != nil) }
  }

  var pan: PanSession? {
    get {
      if case .panning(let session) = interaction { session } else { nil }
    }
    set { setInteraction(newValue.map(Interaction.panning), wasRunning: pan != nil) }
  }

  var drag: MouseDrag? {
    get {
      if case .dragging(let drag) = interaction { drag } else { nil }
    }
    set { setInteraction(newValue.map(Interaction.dragging), wasRunning: drag != nil) }
  }

  /// Sets one kind of interaction, or ends it (`nil`). `wasRunning` is whether that kind was
  /// running before; if it wasn't, it may only start from idle.
  private func setInteraction(_ new: Interaction?, wasRunning: Bool) {
    guard let new else {
      if wasRunning { interaction = .idle }
      return
    }
    if !wasRunning && !interaction.isIdle {
      Self.log.fault("an interaction started while another was still running")
    }
    interaction = new
  }
}

import CoreGraphics
import TylerCore

/// What a controller wants done. Controllers decide and return effects; only the manager carries
/// them out (`run(_:)`), in order, so no controller touches the window system. A controller never
/// depends on an earlier effect having run: the registry changes only through window events.
/// The other effects that move windows carry their moves, worked out when the controller
/// decided: transitions (a slide, a preview, putting a preview back) and parking. `reconcile` and
/// `focusCurrentWorkspace` read the model when they run, after the whole decision, so they stand
/// for its final state.
enum Effect: Equatable {
  /// A slide jumps to its end, a swipe's windows go back where they started.
  case endSlideOrSwipe
  /// The drag is forgotten; what its preview moved is put back by the placements before this.
  case forgetDrag
  /// Each display's current workspace, or only those on `displays`, where the model wants it at
  /// rest: in their slots, or parked when out of view in a scrolling layout. Only the windows
  /// that are off move (see `Reconciler`), or all of them with `force`.
  case reconcile(force: Bool = false, displays: Set<DisplayKey>? = nil)
  case place([Placement])
  /// One step of a resize: quicker than `place`, and settled by a `place` or `reconcile` after.
  case placeInPassing([Placement])
  /// One step of a slide or swipe: a move without a resize.
  case nudge([Nudge])
  /// A window the user moves with the modifier: not remembered as tylerd's move.
  case carry(Nudge)
  case carryFrame(Placement)
  case animate(Transition)
  /// What the drag preview shows, the windows moving there over the duration; a preview still
  /// moving windows hands them over where they are.
  case preview([Placement], over: Duration)
  /// A failure makes the command's reply an error.
  case focus(WindowID)
  case focusCurrentWorkspace
  /// A failure makes the command's reply an error.
  case close(WindowID)
  case restoreOriginalFrames([WindowID])
  /// Where windows a previous tylerd handed over, which appeared late, were before it first moved
  /// them; before anything moves them.
  case rememberOriginalFrames([WindowID: CGRect])
  /// The pointer watches for what the config turns on (the swipe, moves while focus follows the
  /// mouse, drags with the modifier) and stops watching what it turns off.
  case applyPointerSettings
  /// These windows sent to another display have arrived (or left tiling): the mover stops
  /// holding them on their workspace.
  case releaseCrossings(Set<WindowID>)
}

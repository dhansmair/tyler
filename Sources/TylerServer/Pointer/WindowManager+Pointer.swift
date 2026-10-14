import CoreGraphics
import TylerCore

/// The pointer's events, each handed to the feature it is for.
extension WindowManager {
  /// Starts listening to the pointer, if there is one. Subscribes before starting it, like the
  /// window events, so no event is lost.
  func startPointer() {
    guard let pointer else { return }
    let events = pointer.events
    pointerPump = Task { [weak self] in
      for await event in events {
        self?.apply(event)
      }
    }
    pointer.canCapture = { [weak self] in self?.decidesCapture($1, at: $0) ?? false }
    pointer.start()
    applyPointerSettings()
  }

  /// Has the pointer watch for the configured swipe, and for moves while focus follows the mouse;
  /// or stop watching what is turned off.
  func applyPointerSettings() {
    let followsFocus = config.mouse.focusFollows && stacking != nil
    let showsGapCursor = gapHover != nil && stacking != nil && config.mouse.gapResize
    pointer?.watch(
      PointerWatch(
        swipeFingers: config.gestures.swipe ? config.gestures.fingers : nil,
        moves: followsFocus || showsGapCursor,
        modifierKeys: stacking == nil ? [] : config.mouse.modifier,
        gapPresses: stacking != nil && config.mouse.gapResize))
    if !followsFocus { pointerRest.cancel() }
    refreshGapCursor()
  }

  func apply(_ event: PointerEvent) {
    switch event {
    case .primaryButtonDragged(let location): previewDrop(at: location)
    case .primaryButtonReleased(let location):
      gapHover?.pointerMoved(to: location)
      drop(at: location)
    case .swipe(let update, let location): apply(update, at: location)
    case .moved(let location):
      pointerMoved(to: location)
      gapHovered(at: location)
    case .modifierDragBegan(let kind, let location): beginGrab(kind, at: location)
    case .modifierDragMoved(let location): moveGrab(to: location)
    case .modifierDragEnded(let location):
      // Before the drag ends, so the gap cursor is checked again where the pointer is now.
      gapHover?.pointerMoved(to: location)
      endGrab(at: location)
    }
  }
}

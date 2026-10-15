import CoreGraphics
import TylerCore

/// The resize cursor over the gap under the pointer, where a drag would resize.
extension WindowManager {
  func gapHovered(at location: CGPoint) {
    gapHover?.pointerMoved(to: location)
    refreshGapCursor()
  }

  /// Shows the resize cursor over the gap at the pointer's last place, or hides it: after the
  /// pointer moved, and after anything that may have moved the windows around it. The pointer
  /// takes over presses in a gap only while the cursor shows.
  func refreshGapCursor() {
    guard let gapHover else { return }
    let wasShown = gapHover.shown != nil
    gapHover.show(over: hoveredGap(at: gapHover.location, shown: gapHover.shown))
    let isShown = gapHover.shown != nil
    if isShown != wasShown { pointer?.gapHovered(isShown) }
  }

  /// The gap at `location` that a press would grab, or the one being dragged. The window list
  /// is read only when the pointer comes to another gap, not on every move along one.
  private func hoveredGap(at location: CGPoint?, shown: CGRect?) -> CGRect? {
    if let drag, let grab = drag.session.grab, grab.kind == .gap {
      return draggedGap(beside: drag.windowID, grab: grab)
    }
    guard let location, let stacking, config.mouse.gapResize, interaction.isIdle,
      let gap = DragController(context: context).gap(at: location, model: model)
    else { return nil }
    if gap.area == shown { return shown }
    return stacking.topmostWindow(at: location) == nil ? gap.area : nil
  }

  /// The gap a drag moves, where the layout has put it by now: past the grabbed window's edge,
  /// level with where the press was.
  private func draggedGap(beside windowID: WindowID, grab: ModifierGrab) -> CGRect? {
    guard let slot = tiling.slot(of: windowID)?.frame else { return nil }
    let halfGap = context.gaps.inner / 2
    let point =
      grab.edges == .right
      ? CGPoint(x: slot.maxX + halfGap, y: grab.start.y)
      : CGPoint(x: grab.start.x, y: slot.maxY + halfGap)
    return DragController(context: context).gap(at: point, model: model)?.area
  }
}

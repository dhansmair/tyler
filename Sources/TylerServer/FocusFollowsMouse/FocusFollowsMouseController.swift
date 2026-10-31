import CoreGraphics
import TylerCore

/// Focus follows the mouse: the window the pointer rests over gets the focus, and so does an empty
/// workspace, as switching to it would.
struct FocusFollowsMouseController {
  let context: ControllerContext

  /// Focuses the window `PointerFocus` picks. Nothing happens while a button is held or a slide,
  /// swipe or drag moves the windows: those own the windows. Nor outside every display's visible
  /// frame, over the menu bar or the Dock: the Dock's own window spans its whole display, so the
  /// window list can't tell where the Dock is. `subject` names the point for the log.
  func pointerRested(_ verdict: PointerVerdict?, named subject: @autoclosure () -> String)
    -> [Effect]
  {
    if case .refused(let refusal) = verdict {
      context.log.debug("pointer rest ignored - \(subject()) - \(refusal.explanation)")
    }
    return verdict?.window.map { [.focus($0)] } ?? []
  }

  /// The empty workspace under the pointer gets the focus, unless it has it already.
  func pointerRestedOnEmptyWorkspace(
    at location: CGPoint, named subject: @autoclosure () -> String, model: inout Model
  ) -> [Effect] {
    guard model.focusDisplay(under: location, in: context) else { return [] }
    context.log.info("workspace focusing - \(subject()) - the pointer rested on an empty one")
    return [.focusCurrentWorkspace]
  }
}

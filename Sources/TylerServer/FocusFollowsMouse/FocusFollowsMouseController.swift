import CoreGraphics
import TylerCore
import TylerRuntime

/// Focus follows the mouse: the window the pointer rests over gets the focus.
struct FocusFollowsMouseController {
  let log: TylerLog

  /// Focuses the window `PointerFocus` picks. Nothing happens while a button is held or a slide,
  /// swipe or drag moves the windows: those own the windows. Nor outside every display's visible
  /// frame, over the menu bar or the Dock: the Dock's own window spans its whole display, so the
  /// window list can't tell where the Dock is. `subject` names the point for the log.
  func pointerRested(check: PointerCheck?, at subject: @autoclosure () -> String) -> [Effect] {
    let verdict = check?.focus
    if case .refused(let refusal) = verdict {
      log.debug("pointer rest ignored - \(subject()) - \(refusal.explanation)")
    }
    return verdict?.window.map { [.focus($0)] } ?? []
  }
}

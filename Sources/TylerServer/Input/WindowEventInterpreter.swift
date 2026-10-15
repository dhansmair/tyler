import CoreGraphics
import TylerCore

/// What a window event means to tylerd, telling its own moves and focus coming back from the
/// user's.
struct WindowEventInterpreter {
  enum Intent: Equatable {
    /// A window moved or was resized from `from`: a drag may have started or gone on.
    case moved(WindowInfo, from: CGRect?)
    case listsMayHaveChanged
    case focused(WindowID, isEcho: Bool)
    case closed(WindowID)
  }

  /// Windows tylerd asked to focus whose focus event hasn't arrived yet. That event must not be
  /// mistaken for the user switching to a parked window.
  private(set) var expectedFocus: Set<WindowID> = []

  mutating func expectFocus(of windowID: WindowID) {
    expectedFocus.insert(windowID)
  }

  /// `known` is the window as it was before the event.
  mutating func intents(
    for event: WindowEvent, known: WindowInfo?, displays: [DisplayInfo]
  ) -> [Intent] {
    if case .updated(let window) = event, let known {
      // Most updates are moves and resizes, many of them echoes of tylerd's own moves (several
      // per window placed, and one per window per slide step). Only these can change the lists.
      // The move comes first: a drag starts before any re-sync, so a window dragged onto another
      // display is held on its workspace until it is dropped.
      let changesLists = Self.mayChangeLists(from: known, to: window, displays: displays)
      return [.moved(window, from: known.frame)] + (changesLists ? [.listsMayHaveChanged] : [])
    }
    var intents: [Intent] = []
    switch event {
    case .focused(let windowID?):
      intents.append(.focused(windowID, isEcho: expectedFocus.remove(windowID) != nil))
    case .destroyed(let windowID):
      expectedFocus.remove(windowID)
      intents.append(.closed(windowID))
    case .created, .updated, .focused(nil):
      break
    }
    intents.append(.listsMayHaveChanged)
    if case .updated(let window) = event { intents.append(.moved(window, from: nil)) }
    return intents
  }

  /// The window became tileable or stopped being so, or moved onto another display.
  private static func mayChangeLists(
    from old: WindowInfo, to new: WindowInfo, displays: [DisplayInfo]
  ) -> Bool {
    guard old.isTileable == new.isTileable else { return true }
    guard old.frame != new.frame else { return false }
    return DisplayGeometry.display(containing: old.frame, in: displays)?.id
      != DisplayGeometry.display(containing: new.frame, in: displays)?.id
  }
}

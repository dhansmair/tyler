import CoreGraphics
import TylerCore

/// What a window event means to tylerd, telling its own moves and focus coming back from the
/// user's.
struct WindowEventInterpreter {
  enum Intent: Equatable {
    /// A window moved or was resized from `from`: a drag may have started or gone on.
    case moved(WindowInfo, from: CGRect?)
    case listsMayHaveChanged
    /// `from` held the focus before: the first thing to ask of a focus nobody asked for.
    case focused(WindowID, isEcho: Bool, from: FocusedWindow?)
    case closed(WindowID)
    /// The window closed with the focus, or while tylerd was handing the focus on after a close.
    /// Comes before the lists change, so they still hold it.
    case closedWithFocus(FocusedWindow)
  }

  /// Windows tylerd asked to focus whose focus event hasn't arrived yet. That event must not be
  /// mistaken for the user switching to a parked window.
  private(set) var expectedFocus: Set<WindowID> = []

  private(set) var lastFocused: FocusedWindow?

  /// The window a focus nobody asked for just took over from. The app's pick can arrive before
  /// the close of the window it replaces (`macos-behaviour.md`, "The focus after a close").
  private(set) var previousFocused: FocusedWindow?

  /// The window that closed with the focus: every focus comes from it until it is forgotten, as
  /// the app's pick can also arrive after tylerd's own focus of the next window.
  private(set) var closedFocus: FocusedWindow?

  /// Windows tylerd asked to focus, and windows that opened, while a close is remembered: the
  /// first are part of handing the focus on, and the second's focus is no answer to the close.
  private var askedSinceClose: Set<WindowID> = []
  private var openedSinceClose: Set<WindowID> = []

  mutating func expectFocus(of windowID: WindowID) {
    expectedFocus.insert(windowID)
    if closedFocus != nil { askedSinceClose.insert(windowID) }
  }

  /// The window that held the focus when tylerd started: no event names it.
  mutating func holdFocus(on window: WindowInfo) {
    lastFocused = FocusedWindow(id: window.id, kind: window.kind, frame: window.frame)
  }

  mutating func forgetPreviousFocus() {
    previousFocused = nil
  }

  /// A focus from now on is a new one, not the answer to the close.
  mutating func forgetClosedFocus() {
    closedFocus = nil
    askedSinceClose = []
    openedSinceClose = []
  }

  /// `known` is the window as it was before the event.
  mutating func intents(
    for event: WindowEvent, known: WindowInfo?, displays: [DisplayInfo]
  ) -> [Intent] {
    noteLastFocused(from: event)
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
      intents.append(focusIntent(windowID, known: known))
    case .focused(nil):
      lastFocused = nil
    case .destroyed(let windowID):
      if let closed = closeOfTheFocus(windowID, known: known) {
        if closedFocus == nil { closedFocus = closed }
        intents.append(.closedWithFocus(closed))
      }
      intents.append(.closed(windowID))
    case .created(let window):
      if closedFocus != nil { openedSinceClose.insert(window.id) }
    case .updated, .updatedTogether:
      break
    }
    intents.append(.listsMayHaveChanged)
    if case .updated(let window) = event { intents.append(.moved(window, from: nil)) }
    return intents
  }

  /// A window opened since the close is no answer to it, so its focus comes from the window before.
  private mutating func focusIntent(_ windowID: WindowID, known: WindowInfo?) -> Intent {
    let isEcho = expectedFocus.remove(windowID) != nil
    let origin = openedSinceClose.contains(windowID) ? lastFocused : closedFocus ?? lastFocused
    if lastFocused?.id != windowID { previousFocused = isEcho ? nil : lastFocused }
    lastFocused = FocusedWindow(id: windowID, kind: known?.kind, frame: known?.frame)
    return .focused(windowID, isEcho: isEcho, from: origin)
  }

  /// The window closing, if it held the focus: it is the focused window, the one a focus just
  /// left, or one tylerd asked to focus while handing the focus on after a close.
  private mutating func closeOfTheFocus(_ windowID: WindowID, known: WindowInfo?) -> FocusedWindow?
  {
    expectedFocus.remove(windowID)
    let wasAskedSinceClose = askedSinceClose.remove(windowID) != nil
    defer {
      if lastFocused?.id == windowID { lastFocused = nil }
      if previousFocused?.id == windowID { previousFocused = nil }
    }
    if let lastFocused, lastFocused.id == windowID { return lastFocused }
    if let previousFocused, previousFocused.id == windowID { return previousFocused }
    if wasAskedSinceClose {
      return FocusedWindow(id: windowID, kind: known?.kind, frame: known?.frame)
    }
    return nil
  }

  /// A focus can arrive before its window's `created`, and what is known of it is gone with the
  /// window.
  private mutating func noteLastFocused(from event: WindowEvent) {
    switch event {
    case .created(let window), .updated(let window):
      noteLastFocused(window)
    case .updatedTogether(let windows):
      for window in windows { noteLastFocused(window) }
    case .destroyed, .focused:
      break
    }
  }

  private mutating func noteLastFocused(_ window: WindowInfo) {
    guard window.id == lastFocused?.id else { return }
    lastFocused?.kind = window.kind
    lastFocused?.frame = window.frame
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

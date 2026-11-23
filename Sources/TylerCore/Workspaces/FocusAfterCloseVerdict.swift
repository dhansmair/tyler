/// What to do about a focus in view that comes from a window that went away: macOS or the app
/// picked it. Within the close memory (`isAfterClose`), tylerd has handed the focus to the window
/// that took the closed one's place (`handedTo`, or none on a workspace left empty), and another
/// window on a workspace goes back to it, even one the user picked in that moment: the rule is the
/// same with every app (#126). Otherwise only a focus on another display goes back, as macOS picks
/// across displays and what the user types next belongs on theirs; on the same display a hide or
/// a quit leaves the pick to macOS.
package enum FocusAfterCloseVerdict: Equatable, Sendable {
  case follow
  case takeBack

  /// `closedIsGone` asks the window server, so it is asked last.
  package init(
    focused: WindowID, closed: FocusedWindow, closedIsGone: @autoclosure () -> Bool,
    situation: Situation
  ) {
    guard situation.isListed, focused != situation.handedTo,
      situation.isAfterClose || !situation.isOnClosedDisplay,
      closed.leftTheChoiceToMacOS(isGone: closedIsGone())
    else {
      self = .follow
      return
    }
    self = .takeBack
  }

  package struct Situation: Equatable, Sendable {
    package var isAfterClose: Bool
    package var isOnClosedDisplay: Bool
    package var handedTo: WindowID?
    package var isListed: Bool

    package init(
      isAfterClose: Bool, isOnClosedDisplay: Bool, handedTo: WindowID?, isListed: Bool
    ) {
      self.isAfterClose = isAfterClose
      self.isOnClosedDisplay = isOnClosedDisplay
      self.handedTo = handedTo
      self.isListed = isListed
    }
  }
}

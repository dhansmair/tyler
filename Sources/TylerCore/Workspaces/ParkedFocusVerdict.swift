/// What to do about a focus on a parked window that has lasted. When the window that held the focus
/// left the choice to macOS, the user didn't ask for the replacement. When tylerd
/// has just asked the same app for another window (`unmetRequest`), the app ended on the window it
/// remembers: asking once more lands, and if it doesn't, the focus stays there and is followed so
/// keys don't go to a parked window.
package enum ParkedFocusVerdict: Equatable, Sendable {
  case follow
  case decline
  case askAgain(WindowID)

  package init(
    isParked: Bool, previous: FocusedWindow?, previousIsGone: Bool, unmetRequest: FocusRequest?
  ) {
    guard isParked else {
      self = .follow
      return
    }
    if previous?.leftTheChoiceToMacOS(isGone: previousIsGone) == true {
      self = .decline
    } else if let unmetRequest, !unmetRequest.isSecondTry {
      self = .askAgain(unmetRequest.window)
    } else {
      self = .follow
    }
  }
}

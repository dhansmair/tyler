/// What to do about a focus on a parked window that has lasted. When the standard window that held
/// the focus is gone, macOS chose the replacement and the user didn't ask for it. A dialog is
/// different: closing one and focusing a parked window is what its app meant to do. When tylerd
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
    if previous?.kind == .standard && previousIsGone {
      self = .decline
    } else if let unmetRequest, !unmetRequest.isSecondTry {
      self = .askAgain(unmetRequest.window)
    } else {
      self = .follow
    }
  }
}

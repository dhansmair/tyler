/// What to do about a focus in view that comes from a window that closed: macOS or the app picked
/// it, and tylerd has handed the focus to the window that took the closed one's place (`handedTo`,
/// or none on a workspace left empty). Another window on a workspace goes back to that one, even
/// one the user picked in that moment: the rule is the same with every app (#126).
package enum FocusAfterCloseVerdict: Equatable, Sendable {
  case follow
  case takeBack

  package init(
    focused: WindowID, closed: FocusedWindow?, closedIsGone: Bool, handedTo: WindowID?,
    isListed: Bool
  ) {
    guard closed?.leftTheChoiceToMacOS(isGone: closedIsGone) == true, isListed,
      focused != handedTo
    else {
      self = .follow
      return
    }
    self = .takeBack
  }
}

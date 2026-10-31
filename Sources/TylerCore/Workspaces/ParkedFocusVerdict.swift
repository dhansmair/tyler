/// What to do about a focus on a parked window that has lasted. When the standard window that held
/// the focus is gone, macOS chose the replacement and the user didn't ask for it. A dialog is
/// different: closing one and focusing a parked window is what its app meant to do.
package enum ParkedFocusVerdict: Equatable, Sendable {
  case follow
  case decline

  package init(isParked: Bool, previous: FocusedWindow?, previousIsGone: Bool) {
    let macOSChose = previous?.kind == .standard && previousIsGone
    self = isParked && macOSChose ? .decline : .follow
  }
}

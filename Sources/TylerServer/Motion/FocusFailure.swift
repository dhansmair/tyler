import TylerCore

struct FocusFailure {
  let windowID: WindowID
  let error: WindowSystemError

  var description: String { "cannot focus window \(windowID): \(error)" }
}

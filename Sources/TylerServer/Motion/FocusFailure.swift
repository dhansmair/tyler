import TylerCore

struct FocusFailure {
  let windowID: WindowID
  let error: BackendError

  var description: String { "cannot focus window \(windowID): \(error)" }
}

import TylerCore

/// The window that held the focus before a focus event, and whether it is the one remembered as
/// closed with the focus.
struct FocusOrigin: Equatable {
  let window: FocusedWindow
  let isAfterClose: Bool
}

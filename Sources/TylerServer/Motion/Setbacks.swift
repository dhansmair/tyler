/// What went wrong while a command moved and focused windows (see `outcome(_:_:)`).
struct Setbacks {
  /// How many windows could not be placed.
  var unplaced = 0
  /// Why the window that should have got the focus didn't, if it didn't.
  var unfocused: String?
  /// What makes the reply an error instead.
  var focusFailure: FocusFailure?
  /// Why the window to close didn't, which also makes the reply an error.
  var closeFailure: String?
}

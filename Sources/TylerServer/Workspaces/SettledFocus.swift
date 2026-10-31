/// What follows from a focus on a parked window that lasted. `asksAgain` says the effects ask the
/// app for another window, so the wait goes on to see whether the focus moves.
struct SettledFocus {
  let effects: [Effect]
  let asksAgain: Bool
}

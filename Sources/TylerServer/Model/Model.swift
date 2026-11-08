import TylerCore

/// What tylerd decides over. Controllers change it; `WindowManager` owns it.
struct Model: Equatable {
  var rows: DisplayRows
  var bookkeeping = WindowBookkeeping()
  var lateHandOver = LateHandOver()
  var tilingEnabled = true

  /// Floating on its workspace, or floated on none.
  func isFloated(_ windowID: WindowID) -> Bool {
    bookkeeping.floated.contains(windowID)
      || rows.location(holding: windowID).map { location in
        rows[location.position][location.index].flags(of: windowID).contains(.floating)
      } == true
  }
}

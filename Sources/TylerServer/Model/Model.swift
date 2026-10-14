import TylerCore

/// What tylerd decides over. Controllers change it; `WindowManager` owns it.
struct Model: Equatable {
  var rows: DisplayRows
  var bookkeeping = WindowBookkeeping()
  var tilingEnabled = true
}

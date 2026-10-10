@testable import TylerCore

/// Window ids from plain numbers.
func ids(_ values: UInt32...) -> [WindowID] { values.map(WindowID.init) }

/// A workspace holding `values` in order, with `focus` focused if given.
func makeWorkspace(_ values: UInt32..., focus: UInt32? = nil) -> Workspace {
  var workspace = Workspace()
  for value in values { workspace.insert(WindowID(value)) }
  if let focus { workspace.setFocus(WindowID(focus)) }
  return workspace
}

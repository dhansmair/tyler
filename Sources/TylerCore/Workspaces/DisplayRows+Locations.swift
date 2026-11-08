extension DisplayRows {
  /// Where the workspace numbered `number` is: its display's position and its index in that row.
  package func location(ofNumber number: Int) -> (position: Int, index: Int)? {
    for (position, entry) in entries.enumerated() {
      if let index = entry.row.index(ofNumber: number) { return (position, index) }
    }
    return nil
  }

  /// Where the window takes a slot: its display's position and its workspace's index in that
  /// row. A flagged member takes none: `location(holding:)` finds it.
  package func location(of windowID: WindowID) -> (position: Int, index: Int)? {
    for (position, entry) in entries.enumerated() {
      if let index = entry.row.index(containing: windowID) { return (position, index) }
    }
    return nil
  }

  /// The workspace the window is on, flagged or not.
  package func location(holding windowID: WindowID) -> (position: Int, index: Int)? {
    for (position, entry) in entries.enumerated() {
      if let index = entry.row.indices.first(where: { entry.row[$0].holds(windowID) }) {
        return (position, index)
      }
    }
    return nil
  }
}

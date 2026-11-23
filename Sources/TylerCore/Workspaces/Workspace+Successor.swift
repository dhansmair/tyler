extension Workspace {
  /// The tiled window that takes `windowID`'s slot once it leaves: the one after it, or the new
  /// last window. A window that takes no slot has none.
  package func successor(of windowID: WindowID) -> WindowID? {
    guard let index = windows.firstIndex(of: windowID), windows.count > 1 else { return nil }
    return index + 1 < windows.count ? windows[index + 1] : windows[index - 1]
  }
}

extension DisplayRows {
  /// Whether the focused display still shows the workspace it showed in `before`, and that
  /// workspace only lost windows since: what the windows that stay can slide from their old
  /// slots after, as a window arriving has no slot to come from.
  package func focusedWorkspaceOnlyLostWindows(since before: DisplayRows) -> Bool {
    focusedKey == before.focusedKey
      && focused.currentIndex == before.focused.currentIndex
      && Set(focused.current.windows).isSubset(of: before.focused.current.windows)
  }
}

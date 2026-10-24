extension DisplayRows {
  /// Whether the focused display still shows the workspace it showed in `before`, and that
  /// workspace only lost windows since, apart from `joining`: what the windows that stay can slide
  /// from their old slots after, as a window arriving has no slot to come from (`joining` has a
  /// frame of its own to come from).
  package func focusedWorkspaceOnlyLostWindows(
    since before: DisplayRows, apartFrom joining: WindowID? = nil
  ) -> Bool {
    focusedKey == before.focusedKey
      && focused.currentIndex == before.focused.currentIndex
      && Set(focused.current.windows).subtracting(joining.map { [$0] } ?? [])
        .isSubset(of: before.focused.current.windows)
  }
}

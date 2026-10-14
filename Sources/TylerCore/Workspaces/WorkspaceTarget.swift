/// Which workspace a `workspace` or `move-to-workspace` command goes to.
package enum WorkspaceTarget: Codable, Equatable, Sendable {
  /// The previous workspace (the one to the left), wrapping from the first to the last.
  case prev
  /// The next workspace (the one to the right), wrapping from the last to the first.
  case next
  /// A workspace by its 1-based number.
  case number(Int)
}

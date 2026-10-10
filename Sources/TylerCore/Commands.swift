/// A position in the tiling list, relative to the focused window.
public enum ListTarget: String, Codable, CaseIterable, Sendable {
  case next
  case prev
  /// The first window in the list. Users type (and the wire format carries) `master`, the
  /// xmonad term; the Swift name is `main` because SwiftLint's inclusive_language rule rejects
  /// `master` in identifiers.
  case main = "master"
}

public enum TilingMode: String, Codable, CaseIterable, Sendable {
  case on
  case off
  case toggle
}

/// Either one specific layout or the next one in `LayoutKind`'s order.
public enum LayoutChoice: Codable, Equatable, Sendable {
  case set(LayoutKind)
  case next
}

/// Which workspace a `workspace` or `move-to-workspace` command goes to.
public enum WorkspaceTarget: Codable, Equatable, Sendable {
  /// The previous workspace (the one to the left), wrapping from the first to the last.
  case prev
  /// The next workspace (the one to the right), wrapping from the last to the first.
  case next
  /// A workspace by its 1-based number.
  case number(Int)
}

import TylerCore

/// What `tyler start`, `restart` and `status` say about tylerd's access to the windows.
extension WindowAccess {
  private static let settings = "System Settings > Privacy & Security > Accessibility"

  /// The fix for a stale entry of `app`, the app tylerd runs as; `nil` for the terminal.
  private static func staleFix(app: String?) -> String {
    guard let app else {
      return "Run `tyler stop`, remove the terminal app you ran tyler in with − under "
        + "\(settings), add it again with +, and run `tyler start` (see docs/troubleshooting.md)."
    }
    return "Run `tyler stop`, remove \(app) with − under \(settings), and run `tyler start`, "
      + "which asks for the permission again (see docs/troubleshooting.md)."
  }

  /// For the `access` line of `tyler status`.
  var summary: String {
    switch self {
    case .ok: "sees the windows"
    case .notTrusted: "no Accessibility permission"
    case .refused: "Accessibility calls refused although the permission is on"
    case .screenLocked: "waiting for the screen to be unlocked"
    case .checking: "some apps haven't answered yet"
    case .blind: "sees none of the windows on screen"
    }
  }

  /// What is wrong and how to fix it; `nil` when nothing needs fixing. `app` is the app tylerd
  /// runs as (`ServerStatus.appName`), `nil` when the terminal holds its grant.
  func problem(app: String?) -> String? {
    switch self {
    case .ok, .screenLocked, .checking: nil
    case .notTrusted:
      if let app {
        "tylerd has no Accessibility permission yet. Turn on \(app) under \(Self.settings); "
          + "tylerd starts by itself once it is on (if it doesn't within a few seconds, run "
          + "`tyler restart`)."
      } else {
        "tylerd has no Accessibility permission yet. Turn on the terminal app you ran tyler in "
          + "under \(Self.settings) (add it with + if it isn't listed); tylerd starts by itself "
          + "once it is on."
      }
    case .refused:
      "macOS refuses tylerd's Accessibility calls although the permission is on, so its entry "
        + "is probably stale. " + Self.staleFix(app: app)
    case .blind:
      "tylerd sees none of the windows on screen, so its Accessibility entry is probably stale. "
        + Self.staleFix(app: app)
    }
  }

  /// A note for a verdict that needs no fix but explains why nothing is tiled yet.
  var note: String? {
    switch self {
    case .screenLocked: "the screen is locked; tylerd tracks windows once it is unlocked"
    case .checking: "some apps haven't answered yet; `tyler status` says once they have"
    case .ok, .notTrusted, .refused, .blind: nil
    }
  }
}

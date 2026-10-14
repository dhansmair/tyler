/// What macOS reports about the windows right now, read again for `tyler debug windows`.
package struct FreshWindows: Codable, Equatable, Sendable {
  /// The windows the backend tracks, each read again.
  package var tracked: [WindowInfo]
  /// Windows of the apps the backend observes that it doesn't track.
  package var untracked: [WindowInfo]
  /// Regular apps the backend couldn't observe, so none of their windows are tracked.
  package var unattachedApps: [String]

  package init(
    tracked: [WindowInfo], untracked: [WindowInfo] = [], unattachedApps: [String] = []
  ) {
    self.tracked = tracked
    self.untracked = untracked
    self.unattachedApps = unattachedApps
  }
}

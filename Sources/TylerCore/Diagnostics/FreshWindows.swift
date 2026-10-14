/// What macOS reports about the windows right now, read again for `tyler debug windows`.
package struct FreshWindows: Codable, Equatable, Sendable {
  /// The windows the window system tracks, each read again.
  package var tracked: [WindowInfo]
  /// Windows of the apps the window system observes that it doesn't track.
  package var untracked: [WindowInfo]
  /// Regular apps the window system couldn't observe, so none of their windows are tracked.
  package var unattachedApps: [String]
  /// The frontmost app's focused window, read now rather than taken from the last notification.
  /// `nil` if there is none or it couldn't be read.
  package var focusedID: WindowID?

  package init(
    tracked: [WindowInfo], untracked: [WindowInfo] = [], unattachedApps: [String] = [],
    focusedID: WindowID? = nil
  ) {
    self.tracked = tracked
    self.untracked = untracked
    self.unattachedApps = unattachedApps
    self.focusedID = focusedID
  }
}

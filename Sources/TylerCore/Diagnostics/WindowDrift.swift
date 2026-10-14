import CoreGraphics

/// Where tylerd's picture of the windows differs from what macOS reports right now. tylerd reads a
/// window again only when the app notifies it, so a missed notification leaves its picture wrong
/// until the next one (a minimized window that keeps its slot, for example).
package struct WindowDrift: Codable, Equatable, Sendable {
  /// What can differ about one window.
  package enum Field: String, Codable, CaseIterable, Sendable {
    case minimized
    case fullscreen
    case frame
    case title
    case kind
    /// tylerd has the window, but macOS gave nothing for it: it closed, or the read failed.
    case unreadable
    /// The window system tracks the window, but tylerd's own list doesn't have it.
    case unlisted
    /// macOS focuses the window now, but tylerd has another one (or none) as focused: a focus
    /// notification went missing.
    case focus
    /// macOS focuses the window, but its workspace has another one as focused: the one
    /// `window focus` and `window swap` act on.
    case workspaceFocus = "workspace-focus"
  }

  package struct Difference: Codable, Equatable, Sendable {
    package var id: WindowID
    package var appName: String
    package var field: Field
    /// What tylerd believes, and what macOS says, as `window list` would show them.
    package var believed: String
    package var actual: String
  }

  package var differences: [Difference]
  /// How many windows were compared.
  package var checkedCount: Int
  package var untracked: [WindowInfo]
  package var unattachedApps: [String]

  /// Whether tylerd's picture matches macOS's in every respect checked.
  package var isEmpty: Bool {
    differences.isEmpty && untracked.isEmpty && unattachedApps.isEmpty
  }

  /// Compares `believed` (tylerd's list) with `fresh`, in the order of `believed`, then the
  /// windows only the window system has.
  package static func compare(believed: [WindowInfo], fresh: FreshWindows) -> WindowDrift {
    let actual = Dictionary(fresh.tracked.map { ($0.id, $0) }) { first, _ in first }
    var differences: [Difference] = []
    for window in believed {
      guard let now = actual[window.id] else {
        differences.append(
          Difference(
            id: window.id, appName: window.appName, field: .unreadable, believed: "tracked",
            actual: "nothing"))
        continue
      }
      differences += changes(window, now)
    }
    let listed = Set(believed.map(\.id))
    for window in fresh.tracked where !listed.contains(window.id) {
      differences.append(
        Difference(
          id: window.id, appName: window.appName, field: .unlisted, believed: "not listed",
          actual: "tracked by the window system"))
    }
    if let difference = focusDifference(believed: believed, fresh: fresh, actual: actual) {
      differences.append(difference)
    }
    return WindowDrift(
      differences: differences, checkedCount: believed.count, untracked: fresh.untracked,
      unattachedApps: fresh.unattachedApps)
  }

  /// Nothing when macOS reports no focused window: the read may just have failed.
  private static func focusDifference(
    believed: [WindowInfo], fresh: FreshWindows, actual: [WindowID: WindowInfo]
  ) -> Difference? {
    let believedFocus = believed.first(where: \.isFocused)?.id
    guard let focused = fresh.focusedID, believedFocus != focused else { return nil }
    let appName = actual[focused]?.appName ?? believed.first { $0.id == focused }?.appName ?? "?"
    return Difference(
      id: focused, appName: appName, field: .focus,
      believed: believedFocus.map { String($0.rawValue) } ?? "none",
      actual: String(focused.rawValue))
  }

  /// Adds a difference if `reported`, the tiled window macOS last reported focused, isn't
  /// `recorded`, its workspace's focused window.
  package mutating func compareWorkspaceFocus(reported: WindowInfo, recorded: WindowID?) {
    guard recorded != reported.id else { return }
    differences.append(
      Difference(
        id: reported.id, appName: reported.appName, field: .workspaceFocus,
        believed: recorded.map { String($0.rawValue) } ?? "none",
        actual: String(reported.id.rawValue)))
  }

  /// One field as tylerd has it and as macOS reports it.
  private struct Reading {
    let field: Field
    let believed: String
    let actual: String
  }

  private static func changes(_ believed: WindowInfo, _ actual: WindowInfo) -> [Difference] {
    let readings = [
      Reading(
        field: .minimized, believed: yesNo(believed.isMinimized), actual: yesNo(actual.isMinimized)),
      Reading(
        field: .fullscreen, believed: yesNo(believed.isFullscreen),
        actual: yesNo(actual.isFullscreen)),
      Reading(field: .frame, believed: frameText(believed.frame), actual: frameText(actual.frame)),
      Reading(field: .title, believed: believed.title, actual: actual.title),
      Reading(field: .kind, believed: believed.kind.rawValue, actual: actual.kind.rawValue),
    ]
    return readings.filter { $0.believed != $0.actual }.map { reading in
      Difference(
        id: believed.id, appName: believed.appName, field: reading.field,
        believed: reading.believed, actual: reading.actual)
    }
  }

  private static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

  /// Whole points, as `window list` shows frames: a fraction of a point isn't a difference.
  private static func frameText(_ frame: CGRect) -> String {
    "\(Int(frame.minX.rounded())),\(Int(frame.minY.rounded())) "
      + "\(Int(frame.width.rounded()))x\(Int(frame.height.rounded()))"
  }
}

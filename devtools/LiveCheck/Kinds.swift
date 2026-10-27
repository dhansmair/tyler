// `kinds`: what `WindowKind.classify` reads about each window (role, subrole, title-bar buttons),
// with whether its size can be set, next to the kind tylerd gave it. For a window tyler tiles
// that it shouldn't, or the other way round.

import AppKit
import ApplicationServices

/// Leaves titles out: `tyler window list` maps an id to its title.
func kinds(_ given: [String]) throws(UsageError) {
  guard given.count <= 1 else { throw UsageError("kinds [window-id]") }
  var windows = Accessibility.windows()
  if let first = given.first {
    guard let windowID = CGWindowID(first), let window = windows[windowID] else {
      throw UsageError("no window \(first) (see `tyler window list`)")
    }
    windows = [windowID: window]
  }
  let tyler = TylerWindows.load()
  if tyler.isEmpty { print("(tylerd didn't answer: the tyler column is empty)") }
  let rows = windows.map { windowID, window in
    KindRow(windowID: windowID, window: window, tylerKind: tyler[Int(windowID)]?.kind)
  }
  let header = ["id", "app", "role", "subrole", "buttons", "resizable", "size", "tyler"]
  printColumns(
    [header] + rows.sorted { ($0.app, $0.windowID) < ($1.app, $1.windowID) }.map(\.cells))
}

private struct KindRow {
  let windowID: CGWindowID
  let app: String
  let cells: [String]

  init(windowID: CGWindowID, window: AXUIElement, tylerKind: String?) {
    self.windowID = windowID
    var pid = pid_t(0)
    app =
      AXUIElementGetPid(window, &pid) == .success
      ? NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)" : "?"
    let buttons = [
      (kAXCloseButtonAttribute, "close"), (kAXMinimizeButtonAttribute, "minimize"),
      (kAXFullScreenButtonAttribute, "full-screen"),
    ]
    .filter { Accessibility.value($0.0, of: window) != nil }.map(\.1)
    var isResizable = DarwinBoolean(false)
    let resizable =
      AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &isResizable)
        != .success ? "?" : isResizable.boolValue ? "yes" : "no"
    let size = Accessibility.size(of: window).map { "\(Int($0.width))x\(Int($0.height))" }
    cells = [
      "\(windowID)", app,
      Accessibility.value(kAXRoleAttribute, of: window) as? String ?? "-",
      Accessibility.value(kAXSubroleAttribute, of: window) as? String ?? "-",
      buttons.isEmpty ? "-" : buttons.joined(separator: ","),
      resizable, size ?? "?", tylerKind ?? "-",
    ]
  }
}

private func printColumns(_ rows: [[String]]) {
  let widths = rows[0].indices.map { column in rows.map { $0[column].count }.max() ?? 0 }
  for row in rows {
    let padded = zip(row, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
    print(padded.joined(separator: "  ").trimmingCharacters(in: .whitespaces))
  }
}

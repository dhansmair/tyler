import CoreGraphics
import TylerCore
import TylerProtocol

extension WindowManager {
  // MARK: - Placing windows

  /// Whether tiling runs: permission has been granted and tiling is on.
  var isTiling: Bool { state == .running && tilingEnabled }

  /// The configured space around and between tiled windows, the same on every workspace.
  var gaps: LayoutGaps { LayoutGaps(config.gaps) }

  /// Where tiling puts each window now, on the connected displays.
  var tiling: TilingSnapshot {
    TilingSnapshot(rows: rows, displays: connectedDisplays, gaps: gaps)
  }

  @discardableResult
  func place(_ placements: [Placement]) -> Int {
    mover.place(placements, known: registry)
  }

  /// How the log names `windowID`: its number, app and title, from the registry.
  func named(_ windowID: WindowID) -> String {
    WindowInfo.logName(windowID, registry.window(withID: windowID))
  }

  func requestFocus(_ windowID: WindowID) throws(WindowSystemError) {
    let expectsEvent = registry.focusedID != windowID
    try mover.focus(windowID, known: registry)
    if expectsEvent { interpreter.expectFocus(of: windowID) }
  }

  func outcome(failures: Int) -> Response {
    outcome(nil, Setbacks(unplaced: failures))
  }

  /// The reply to a command that did what it was asked: `summary`, if any, followed by what went
  /// wrong on the way, so a failed placement or focus never hides what the command did.
  func outcome(_ summary: String?, _ setbacks: Setbacks) -> Response {
    var parts = summary.map { [$0] } ?? []
    let unplaced = setbacks.unplaced
    if unplaced > 0 {
      parts.append("\(unplaced) window\(unplaced == 1 ? "" : "s") could not be placed")
    }
    if let unfocused = setbacks.unfocused { parts.append(unfocused) }
    return parts.isEmpty ? .ok : .message(parts.joined(separator: "; "))
  }
}

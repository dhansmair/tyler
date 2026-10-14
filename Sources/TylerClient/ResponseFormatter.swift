import Foundation
import TylerCore
import TylerProtocol

/// Renders a `Response` for the terminal.
package enum ResponseFormatter {
  /// Returns the text to print and whether the command succeeded.
  package static func format(
    _ response: Response,
    as format: OutputFormat = .text
  ) -> (text: String, success: Bool) {
    switch response {
    case .pong:
      return ("pong", true)
    case .ok:
      return ("", true)
    case .message(let text):
      return (text, true)
    case .windows(let windows):
      return (format == .json ? json(of: windows) : table(of: windows), true)
    case .status(let status):
      // `tyler status` builds its full report in `DaemonController`; this is the short form.
      return ("tylerd is running (pid \(status.pid))", true)
    case .pointer, .drift:
      return (debugReport(of: response, as: format), true)
    case .error(let message):
      return (message, false)
    }
  }

  /// Columns: id, workspace, slot, app, title, frame, display, flags. An empty list prints one line.
  static func table(of windows: [WindowInfo]) -> String {
    guard !windows.isEmpty else { return "no windows" }
    let rows = windows.map { window in
      [
        String(window.id.rawValue),
        window.workspace.map(String.init) ?? "-",
        window.slot.map(String.init) ?? "-",
        window.appName,
        window.title.isEmpty ? "-" : singleLine(window.title),
        frameDescription(window.frame),
        displayDescription(of: window),
        flags(of: window),
      ]
    }
    let header = ["ID", "WORKSPACE", "SLOT", "APP", "TITLE", "FRAME", "DISPLAY", "FLAGS"]
    return columns([header] + rows).joined(separator: "\n")
  }

  /// The rows with their columns lined up, two spaces apart.
  static func columns(_ rows: [[String]]) -> [String] {
    let count = rows.map(\.count).max() ?? 0
    let widths = (0..<count).map { column in
      rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0
    }
    return rows.map { row in
      row.indices.map { column in
        // The last column is not padded, so lines carry no trailing whitespace.
        column == row.count - 1 ? row[column] : row[column].padded(to: widths[column])
      }.joined(separator: "  ")
    }
  }

  static func json(of value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value),
      let text = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return text
  }

  /// The display tyler numbers the window's display with, or its id from an older tylerd.
  static func displayDescription(of window: WindowInfo) -> String {
    if let number = window.displayNumber { return String(number) }
    return window.displayID.map(String.init) ?? "-"
  }

  static func flags(of window: WindowInfo) -> String {
    var result: [String] = []
    if window.isFocused { result.append("focused") }
    if window.isMinimized { result.append("min") }
    if window.isFullscreen { result.append("full") }
    if window.isFloated { result.append("floated") }
    switch window.kind {
    case .standard: break
    case .dialog: result.append("dialog")
    case .floating: result.append("float")
    case .other: result.append("other")
    }
    return result.isEmpty ? "-" : result.joined(separator: ",")
  }

  static func frameDescription(_ frame: CGRect) -> String {
    "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
  }

  static func singleLine(_ text: String) -> String {
    text.replacingOccurrences(of: "\n", with: " ")
  }
}

extension String {
  fileprivate func padded(to width: Int) -> String {
    count >= width ? self : self + String(repeating: " ", count: width - count)
  }
}

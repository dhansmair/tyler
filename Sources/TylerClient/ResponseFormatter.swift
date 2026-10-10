import Foundation
import TylerCore

/// Renders a `Response` for the terminal.
public enum ResponseFormatter {
  /// Returns the text to print and whether the command succeeded.
  public static func format(
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
      switch format {
      case .text:
        return (table(of: windows), true)
      case .json:
        return (json(of: windows), true)
      }
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
        window.displayID.map(String.init) ?? "-",
        flags(of: window),
      ]
    }
    let header = ["ID", "WORKSPACE", "SLOT", "APP", "TITLE", "FRAME", "DISPLAY", "FLAGS"]
    let all = [header] + rows
    let widths = header.indices.map { column in
      all.map { $0[column].count }.max() ?? 0
    }
    return all.map { row in
      row.indices.map { column in
        // The last column is not padded, so lines carry no trailing whitespace.
        column == row.count - 1 ? row[column] : row[column].padded(to: widths[column])
      }.joined(separator: "  ")
    }.joined(separator: "\n")
  }

  static func json(of windows: [WindowInfo]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(windows),
      let text = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return text
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

  private static func frameDescription(_ frame: CGRect) -> String {
    "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
  }

  private static func singleLine(_ text: String) -> String {
    text.replacingOccurrences(of: "\n", with: " ")
  }
}

extension String {
  fileprivate func padded(to width: Int) -> String {
    count >= width ? self : self + String(repeating: " ", count: width - count)
  }
}

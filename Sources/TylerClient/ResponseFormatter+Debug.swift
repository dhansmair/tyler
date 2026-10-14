import CoreGraphics
import TylerCore
import TylerProtocol

/// The answers of the `debug` commands.
extension ResponseFormatter {
  static func debugReport(of response: Response, as format: OutputFormat) -> String {
    switch response {
    case .pointer(let diagnosis):
      return format == .json ? json(of: diagnosis) : report(of: diagnosis)
    case .drift(let drift):
      return format == .json ? json(of: drift) : report(of: drift)
    case .pong, .ok, .message, .windows, .status, .error:
      return ""
    }
  }

  /// `tyler debug windows`: one line per difference, then what only macOS has.
  static func report(of drift: WindowDrift) -> String {
    guard !drift.isEmpty else { return "no differences in \(drift.checkedCount) windows" }
    var lines = columns(
      drift.differences.map { difference in
        [
          String(difference.id.rawValue), difference.appName, difference.field.rawValue,
          "tylerd: \(difference.believed)", "macOS: \(difference.actual)",
        ]
      })
    if !drift.untracked.isEmpty {
      lines.append("windows tylerd doesn't track:")
      lines += drift.untracked.map { window in
        let title = window.title.isEmpty ? "" : " \"\(singleLine(window.title))\""
        return "  \(window.id.rawValue) \(window.appName)\(title), \(flags(of: window))"
      }
    }
    if !drift.unattachedApps.isEmpty {
      lines.append("apps tylerd can't observe: " + drift.unattachedApps.joined(separator: ", "))
    }
    return lines.joined(separator: "\n")
  }

  /// `tyler debug at`: one line per fact, then the two decisions.
  static func report(of diagnosis: PointerDiagnosis) -> String {
    let check = diagnosis.check
    let point = "\(Int(diagnosis.point.x)),\(Int(diagnosis.point.y))"
    let display =
      diagnosis.displayNumber.map { number in
        let visible = diagnosis.visibleFrame.map(frameDescription) ?? "-"
        return "display \(number), visible frame \(visible)"
      } ?? "no display"
    let lines = [
      ("point", "\(point), on \(display)"),
      ("on top", onTop(diagnosis.onTop)),
      ("menu open", check.isMenuOpen ? "yes" : "no"),
      ("interaction", diagnosis.interaction),
      ("tiling", check.isTiling ? "on" : "off"),
      ("modifier", diagnosis.modifier.isEmpty ? "none" : diagnosis.modifier),
      ("grab", verdict(diagnosis.grab)),
      ("focus", verdict(diagnosis.focus)),
    ]
    return lines.map { label, value in
      label + String(repeating: " ", count: 13 - label.count) + value
    }.joined(separator: "\n")
  }

  private static func onTop(_ onTop: PointerDiagnosis.OnTop?) -> String {
    guard let onTop else { return "nothing (the Dock's window is left out)" }
    var parts = ["window \(onTop.id.rawValue)"]
    if let appName = onTop.appName {
      let title = onTop.title.map { $0.isEmpty ? "" : " \"\($0)\"" } ?? ""
      parts[0] += " (\(appName)\(title))"
    } else {
      if let owner = onTop.owner { parts[0] += " (\(owner))" }
      parts.append("not tracked")
    }
    parts.append("layer \(onTop.layer)")
    parts.append(onTop.workspace.map { "workspace \($0)" } ?? "on no workspace")
    return parts.joined(separator: ", ")
  }

  private static func verdict(_ verdict: PointerVerdict) -> String {
    switch verdict {
    case .window(let windowID): "yes, window \(windowID.rawValue)"
    case .refused(let refusal): "no: \(refusal.explanation)"
    }
  }
}

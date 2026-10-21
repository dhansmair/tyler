import Foundation
import TylerCore

/// What `tyler status` says about tylerd's event listeners.
extension InputListener {
  /// The `input` line, and a line for each listener macOS turned off; `now` says how long ago.
  static func statusLines(_ listeners: [InputListener], now: Date) -> [String] {
    let names = listeners.map {
      $0.isListening ? $0.kind.rawValue : "\($0.kind.rawValue) (refused by macOS)"
    }
    var lines = ["  input   " + (names.isEmpty ? "none" : names.joined(separator: ", "))]
    for listener in listeners where listener.timesTurnedOff > 0 {
      let times = listener.timesTurnedOff == 1 ? "once" : "\(listener.timesTurnedOff) times"
      let ago = listener.lastTurnedOff.map {
        " (last \(DaemonController.describe(uptime: now.timeIntervalSince($0))) ago)"
      }
      let name = listener.kind.rawValue
      lines.append("          \(name) turned off by macOS \(times)\(ago ?? ""), turned back on")
    }
    return lines
  }
}

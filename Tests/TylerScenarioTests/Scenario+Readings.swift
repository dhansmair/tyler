import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

/// What the user sees: the lists, the frames, the focus, which windows are parked.
extension Scenario {
  func frame(of window: UInt32) -> CGRect? {
    harness.frame(of: window)
  }

  /// The windows of workspace `number`, in list order.
  func list(_ number: Int) -> [UInt32] {
    harness.manager.listed
      .filter { $0.workspace == number && $0.slot != nil }
      .sorted { ($0.slot ?? 0) < ($1.slot ?? 0) }
      .map(\.id.rawValue)
  }

  /// What `tyler window list` shows.
  var windowList: [WindowInfo] {
    harness.manager.listed
  }

  /// Window id → workspace number, for the windows on a workspace.
  var workspaces: [UInt32: Int] {
    harness.workspaces()
  }

  /// What tylerd asked macOS to do (moves, focus, closes), and the refusals a test sets up.
  var windowSystem: FakeWindowSystem {
    harness.windowSystem
  }

  /// The workspace each display shows, by display number.
  var shown: [Int] {
    harness.manager.rows.entries.map { $0.row.number(at: $0.row.currentIndex) }
  }

  /// The window tylerd last focused.
  var focused: UInt32? {
    harness.windowSystem.focusCalls.last?.rawValue
  }

  /// Whether `window` waits just past the parking edge of one of the displays.
  func isParked(_ window: UInt32) -> Bool {
    guard let frame = frame(of: window) else { return false }
    return harness.manager.rows.keys.contains { key in
      harness.manager.display(for: key).map { frame == Parking.frame(for: frame, on: $0) } == true
    }
  }

  /// `region` of display `number`'s visible frame (without the menu bar and the Dock), its edges
  /// rounded to whole points as the layouts round them. Worked out here, not by the layout under
  /// test.
  func rect(_ region: Region, display number: Int = 1) -> CGRect {
    let keys = harness.manager.rows.keys
    guard keys.indices.contains(number - 1),
      let area = harness.manager.display(for: keys[number - 1])?.visibleFrame
    else {
      Issue.record("no display \(number)")
      return .null
    }
    return region.rect(in: area)
  }

  /// The layout of workspace `number`, as the menu bar shows it while it is on screen.
  func layout(_ number: Int) -> LayoutKind? {
    harness.manager.rows.entries.lazy
      .compactMap { entry in entry.row.index(ofNumber: number).map { entry.row[$0].layout } }
      .first
  }

  /// The number of the display that has the focus, where the next command goes.
  var focusedDisplay: Int? {
    harness.manager.rows.keys.firstIndex(of: harness.manager.rows.focusedKey).map { $0 + 1 }
  }

  /// The workspaces each display holds, by display number, in the order the menu bar map shows.
  var rows: [[Int]] {
    harness.manager.rows.entries.map(\.row.numbers)
  }
}

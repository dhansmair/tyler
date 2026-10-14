import CoreGraphics
import Testing

@testable import TylerCore

@Suite("WindowDrift")
struct WindowDriftTests {
  typealias Edit = (inout WindowInfo) -> Void

  private static func window(_ id: UInt32, _ edit: Edit = { _ in }) -> WindowInfo {
    var window = WindowInfo(
      id: WindowID(id), processID: 500, appName: "App", title: "t",
      frame: CGRect(x: 10, y: 20, width: 300, height: 200), kind: .standard, isMinimized: false,
      isFullscreen: false, isFocused: false)
    edit(&window)
    return window
  }

  @Test func theSamePictureHasNoDifferences() {
    let drift = WindowDrift.compare(
      believed: [Self.window(1), Self.window(2)],
      fresh: FreshWindows(tracked: [Self.window(2), Self.window(1)]))
    #expect(drift.isEmpty)
    #expect(drift.checkedCount == 2)
  }

  struct Case: CustomTestStringConvertible, Sendable {
    let field: WindowDrift.Field
    let change: @Sendable (inout WindowInfo) -> Void
    let believed: String
    let actual: String
    var testDescription: String { field.rawValue }
  }

  @Test(arguments: [
    Case(field: .minimized, change: { $0.isMinimized = true }, believed: "no", actual: "yes"),
    Case(field: .fullscreen, change: { $0.isFullscreen = true }, believed: "no", actual: "yes"),
    Case(
      field: .frame, change: { $0.frame.origin.x = 40 }, believed: "10,20 300x200",
      actual: "40,20 300x200"),
    Case(field: .title, change: { $0.title = "new" }, believed: "t", actual: "new"),
    Case(field: .kind, change: { $0.kind = .dialog }, believed: "standard", actual: "dialog"),
  ])
  func eachFieldIsCompared(_ test: Case) {
    let drift = WindowDrift.compare(
      believed: [Self.window(1)], fresh: FreshWindows(tracked: [Self.window(1, test.change)]))
    let expected = WindowDrift.Difference(
      id: WindowID(1), appName: "App", field: test.field, believed: test.believed,
      actual: test.actual)
    #expect(drift.differences == [expected])
  }

  @Test func aFractionOfAPointIsNoDifference() {
    let drift = WindowDrift.compare(
      believed: [Self.window(1)],
      fresh: FreshWindows(tracked: [Self.window(1) { $0.frame.origin.x = 10.3 }]))
    #expect(drift.isEmpty)
  }

  @Test func windowsOnOnlyOneSideAreReported() {
    let drift = WindowDrift.compare(
      believed: [Self.window(1), Self.window(2)],
      fresh: FreshWindows(
        tracked: [Self.window(2), Self.window(3)], untracked: [Self.window(4)],
        unattachedApps: ["Busy"]))
    #expect(drift.differences.map(\.id) == [WindowID(1), WindowID(3)])
    #expect(drift.differences.map(\.field) == [.unreadable, .unlisted])
    #expect(drift.untracked.map(\.id) == [WindowID(4)])
    #expect(drift.unattachedApps == ["Busy"])
    #expect(!drift.isEmpty)
  }

  @Test func theWorkspaceFocusingTheReportedWindowIsNoDifference() {
    var drift = WindowDrift.compare(believed: [], fresh: FreshWindows(tracked: []))
    drift.compareWorkspaceFocus(reported: Self.window(1), recorded: WindowID(1))
    #expect(drift.isEmpty)
  }

  @Test(arguments: [WindowID(2), nil])
  func theWorkspaceFocusingAnotherWindowIsReported(recorded: WindowID?) {
    var drift = WindowDrift.compare(believed: [], fresh: FreshWindows(tracked: []))
    drift.compareWorkspaceFocus(reported: Self.window(1), recorded: recorded)
    #expect(drift.differences.map(\.field) == [.workspaceFocus])
    #expect(drift.differences.first?.id == WindowID(1))
    #expect(drift.differences.first?.believed == (recorded == nil ? "none" : "2"))
    #expect(drift.differences.first?.actual == "1")
  }

  @Test func aFocusMacOSReportsAsTylerdHasItIsNoDifference() {
    let believed = [Self.window(1) { $0.isFocused = true }, Self.window(2)]
    let drift = WindowDrift.compare(
      believed: believed,
      fresh: FreshWindows(tracked: [Self.window(1), Self.window(2)], focusedID: WindowID(1)))
    #expect(drift.isEmpty)
  }

  @Test(arguments: [WindowID(1), nil])
  func aFocusTylerdMissedIsReported(believedFocus: WindowID?) {
    let believed = [1, 2].map { id in Self.window(id) { $0.isFocused = $0.id == believedFocus } }
    let drift = WindowDrift.compare(
      believed: believed,
      fresh: FreshWindows(tracked: [Self.window(1), Self.window(2)], focusedID: WindowID(2)))
    #expect(drift.differences.map(\.field) == [.focus])
    #expect(drift.differences.first?.id == WindowID(2))
    #expect(drift.differences.first?.believed == (believedFocus == nil ? "none" : "1"))
    #expect(drift.differences.first?.actual == "2")
  }

  @Test func noFocusReadFromMacOSIsNoDifference() {
    let drift = WindowDrift.compare(
      believed: [Self.window(1) { $0.isFocused = true }],
      fresh: FreshWindows(tracked: [Self.window(1)]))
    #expect(drift.isEmpty)
  }
}

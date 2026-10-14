import Testing
import TylerCore

@Suite("Window log names")
struct WindowInfoLogNameTests {
  private static func window(title: String) -> WindowInfo {
    WindowInfo(
      id: WindowID(7349), processID: 1, appName: "Firefox", title: title, frame: .zero,
      kind: .standard, isMinimized: false, isFullscreen: false, isFocused: false)
  }

  @Test(arguments: ["Instagram", "", "Inbox – someone"])
  func aWindowIsNamedByItsAppNotItsTitle(title: String) {
    #expect(WindowInfo.logName(WindowID(7349), Self.window(title: title)) == "#7349 (Firefox)")
  }

  @Test func aWindowOnTopIsNamedByItsOwner() {
    #expect(
      StackedWindow(id: WindowID(3), layer: 25, owner: "Window Server").logName
        == "#3 (Window Server)")
    #expect(StackedWindow(id: WindowID(3), layer: 25).logName == "#3")
  }

  @Test func anUnknownWindowIsJustItsNumber() {
    #expect(WindowInfo.logName(WindowID(7349), nil) == "#7349")
  }
}

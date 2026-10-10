import Testing
import TylerCore

@testable import TylerServer

@Suite("WindowRegistry")
struct WindowRegistryTests {
  private func ids(_ registry: WindowRegistry) -> [UInt32] {
    registry.windows.map(\.id.rawValue)
  }

  @Test func startsEmpty() {
    let registry = WindowRegistry()
    #expect(registry.windows.count == 0)
    #expect(registry.windows.isEmpty)
    #expect(registry.focusedID == nil)
  }

  @Test func createdWindowsKeepTheOrderTheyWereSeenIn() {
    var registry = WindowRegistry()
    for windowID: UInt32 in [30, 10, 20] {
      registry.apply(.created(makeWindow(id: windowID)))
    }
    #expect(ids(registry) == [30, 10, 20])
  }

  @Test func aDuplicateCreateUpdatesInsteadOfAddingTwice() {
    var registry = WindowRegistry()
    registry.apply(.created(makeWindow(id: 1, title: "old")))
    registry.apply(.created(makeWindow(id: 1, title: "new")))
    #expect(registry.windows.count == 1)
    #expect(registry.windows.first?.title == "new")
  }

  @Test func anUpdateForAnUnknownWindowInsertsIt() {
    var registry = WindowRegistry()
    registry.apply(.updated(makeWindow(id: 7, title: "early move")))
    #expect(ids(registry) == [7])
  }

  @Test func updatesKeepPosition() {
    var registry = WindowRegistry()
    registry.apply(.created(makeWindow(id: 1)))
    registry.apply(.created(makeWindow(id: 2)))
    registry.apply(.updated(makeWindow(id: 1, title: "changed")))
    #expect(ids(registry) == [1, 2])
    #expect(registry.windows.first?.title == "changed")
  }

  @Test func destroyedRemovesTheWindow() {
    var registry = WindowRegistry()
    registry.apply(.created(makeWindow(id: 1)))
    registry.apply(.created(makeWindow(id: 2)))
    registry.apply(.destroyed(WindowID(1)))
    #expect(ids(registry) == [2])
  }

  @Test func destroyingAnUnknownWindowIsIgnored() {
    var registry = WindowRegistry()
    registry.apply(.created(makeWindow(id: 1)))
    registry.apply(.destroyed(WindowID(99)))
    #expect(ids(registry) == [1])
  }

  @Test func focusMarksExactlyOneWindow() {
    var registry = WindowRegistry()
    registry.apply(.created(makeWindow(id: 1)))
    registry.apply(.created(makeWindow(id: 2)))
    registry.apply(.focused(WindowID(2)))
    #expect(registry.windows.map(\.isFocused) == [false, true])
    registry.apply(.focused(WindowID(1)))
    #expect(registry.windows.map(\.isFocused) == [true, false])
  }

  @Test func focusCanBeCleared() {
    var registry = WindowRegistry()
    registry.apply(.created(makeWindow(id: 1)))
    registry.apply(.focused(WindowID(1)))
    registry.apply(.focused(nil))
    #expect(registry.windows.map(\.isFocused) == [false])
  }

  @Test func destroyingTheFocusedWindowClearsFocus() {
    var registry = WindowRegistry()
    registry.apply(.created(makeWindow(id: 1)))
    registry.apply(.focused(WindowID(1)))
    registry.apply(.destroyed(WindowID(1)))
    #expect(registry.focusedID == nil)
  }

  @Test func focusArrivingBeforeTheCreateStillApplies() {
    var registry = WindowRegistry()
    registry.apply(.focused(WindowID(5)))
    registry.apply(.created(makeWindow(id: 5)))
    #expect(registry.windows.map(\.isFocused) == [true])
  }

  @Test func replaceAllDiscardsOldStateAndFollowsTheFocusedFlag() {
    var registry = WindowRegistry()
    registry.apply(.created(makeWindow(id: 1)))
    registry.apply(.focused(WindowID(1)))
    registry.replaceAll([makeWindow(id: 8), makeWindow(id: 9, isFocused: true)])
    #expect(ids(registry) == [8, 9])
    #expect(registry.focusedID == WindowID(9))
  }
}

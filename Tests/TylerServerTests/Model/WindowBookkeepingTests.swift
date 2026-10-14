import CoreGraphics
import Testing
import TylerCore

@testable import TylerServer

@Suite("WindowBookkeeping")
struct WindowBookkeepingTests {
  private let frame = CGRect(x: 10, y: 20, width: 300, height: 200)

  @Test func forgettingAWindowClearsEverythingKeptAboutIt() {
    var bookkeeping = WindowBookkeeping()
    for windowID in [WindowID(1), WindowID(2)] {
      bookkeeping.floated.insert(windowID)
      bookkeeping.seen.insert(windowID)
    }
    bookkeeping.forget(WindowID(1))
    #expect(bookkeeping.floated == [WindowID(2)])
    #expect(bookkeeping.seen == [WindowID(2)])
  }

  @Test func restoringKeepsOnlyWindowsThatStillExist() {
    let saved = SavedState(
      row: WorkspaceRow(count: 2), floated: [WindowID(1), WindowID(2)], tilingEnabled: true,
      originalFrames: [WindowID(1): frame, WindowID(2): frame], seen: [WindowID(1), WindowID(2)])
    let bookkeeping = WindowBookkeeping(restoring: saved, known: [WindowID(2), WindowID(3)])
    #expect(bookkeeping.floated == [WindowID(2)])
    #expect(bookkeeping.seen == [WindowID(2)])
  }
}

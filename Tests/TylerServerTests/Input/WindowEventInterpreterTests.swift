import CoreGraphics
import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("WindowEventInterpreter")
struct WindowEventInterpreterTests {
  private static let left = DisplayInfo(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 600))
  private static let right = DisplayInfo(
    id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 600),
    visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 600))
  private static let displays = [left, right]

  @Test func aFocusTylerAskedForIsItsOwnEchoOnce() {
    var interpreter = WindowEventInterpreter()
    interpreter.expectFocus(of: WindowID(2))
    let first = interpreter.intents(for: .focused(WindowID(2)), known: nil, displays: [])
    let second = interpreter.intents(for: .focused(WindowID(2)), known: nil, displays: [])
    #expect(first.first == .focused(WindowID(2), isEcho: true))
    #expect(second.first == .focused(WindowID(2), isEcho: false), "the next focus is the user's")
  }

  @Test func aMoveOnTheSameDisplayLeavesTheLists() {
    var interpreter = WindowEventInterpreter()
    let before = makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200))
    let after = makeWindow(id: 1, frame: CGRect(x: 140, y: 100, width: 300, height: 200))
    #expect(
      interpreter.intents(for: .updated(after), known: before, displays: Self.displays)
        == [.moved(after)])
  }

  @Test func aMoveOntoAnotherDisplayMayChangeTheLists() {
    var interpreter = WindowEventInterpreter()
    let before = makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200))
    let after = makeWindow(id: 1, frame: CGRect(x: 1100, y: 100, width: 300, height: 200))
    #expect(
      interpreter.intents(for: .updated(after), known: before, displays: Self.displays)
        == [.moved(after), .listsMayHaveChanged])
  }

  @Test func aClosedWindowIsNoLongerExpectedToTakeFocus() {
    var interpreter = WindowEventInterpreter()
    interpreter.expectFocus(of: WindowID(2))
    let intents = interpreter.intents(for: .destroyed(WindowID(2)), known: nil, displays: [])
    #expect(intents == [.closed(WindowID(2)), .listsMayHaveChanged])
    #expect(interpreter.expectedFocus.isEmpty)
  }
}

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
    let previous = FocusedWindow(id: WindowID(2), kind: nil)
    #expect(first.first == .focused(WindowID(2), isEcho: true, from: nil))
    #expect(
      second.first == .focused(WindowID(2), isEcho: false, from: previous),
      "the next focus is the user's")
  }

  @Test func aMoveOnTheSameDisplayLeavesTheLists() {
    var interpreter = WindowEventInterpreter()
    let before = makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200))
    let after = makeWindow(id: 1, frame: CGRect(x: 140, y: 100, width: 300, height: 200))
    #expect(
      interpreter.intents(for: .updated(after), known: before, displays: Self.displays)
        == [.moved(after, from: before.frame)])
  }

  @Test func aMoveOntoAnotherDisplayMayChangeTheLists() {
    var interpreter = WindowEventInterpreter()
    let before = makeWindow(id: 1, frame: CGRect(x: 100, y: 100, width: 300, height: 200))
    let after = makeWindow(id: 1, frame: CGRect(x: 1100, y: 100, width: 300, height: 200))
    #expect(
      interpreter.intents(for: .updated(after), known: before, displays: Self.displays)
        == [.moved(after, from: before.frame), .listsMayHaveChanged])
  }

  @Test func aClosedWindowIsNoLongerExpectedToTakeFocus() {
    var interpreter = WindowEventInterpreter()
    interpreter.expectFocus(of: WindowID(2))
    let intents = interpreter.intents(for: .destroyed(WindowID(2)), known: nil, displays: [])
    #expect(intents == [.closed(WindowID(2)), .listsMayHaveChanged])
    #expect(interpreter.expectedFocus.isEmpty)
  }

  @Test func aFocusCarriesTheWindowFocusedBeforeItEvenIfItClosed() {
    var interpreter = WindowEventInterpreter()
    let first = makeWindow(id: 1)
    _ = interpreter.intents(for: .focused(first.id), known: first, displays: [])
    _ = interpreter.intents(for: .destroyed(first.id), known: nil, displays: [])
    let intents = interpreter.intents(for: .focused(WindowID(2)), known: nil, displays: [])
    let previous = FocusedWindow(id: first.id, kind: .standard, frame: first.frame)
    #expect(intents.first == .focused(WindowID(2), isEcho: false, from: previous))
  }

  @Test func aWindowFocusedBeforeItsCreationLearnsItsKind() {
    var interpreter = WindowEventInterpreter()
    let window = makeWindow(id: 1, kind: .dialog)
    _ = interpreter.intents(for: .focused(window.id), known: nil, displays: [])
    _ = interpreter.intents(for: .created(window), known: nil, displays: [])
    #expect(interpreter.lastFocused?.kind == .dialog)
  }

  @Test func noFocusedWindowForgetsTheLastOne() {
    var interpreter = WindowEventInterpreter()
    _ = interpreter.intents(for: .focused(WindowID(1)), known: nil, displays: [])
    _ = interpreter.intents(for: .focused(nil), known: nil, displays: [])
    #expect(interpreter.lastFocused == nil)
  }

  @Test func forgettingOnlyTouchesThatWindow() {
    var interpreter = WindowEventInterpreter()
    _ = interpreter.intents(for: .focused(WindowID(1)), known: nil, displays: [])
    interpreter.forgetFocus(of: WindowID(2))
    #expect(interpreter.lastFocused?.id == WindowID(1))
    interpreter.forgetFocus(of: WindowID(1))
    #expect(interpreter.lastFocused == nil)
  }
}

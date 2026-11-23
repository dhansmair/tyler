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

  // MARK: - The focused window closing

  @Test func theFocusedWindowClosingSaysSoBeforeTheListsChange() {
    var interpreter = WindowEventInterpreter()
    let first = makeWindow(id: 1)
    _ = interpreter.intents(for: .focused(first.id), known: first, displays: [])
    let intents = interpreter.intents(for: .destroyed(first.id), known: nil, displays: [])
    #expect(
      intents == [
        .closedWithFocus(Self.focused(first)), .closed(first.id), .listsMayHaveChanged,
      ])
  }

  @Test func anotherWindowClosingIsJustAClose() {
    var interpreter = WindowEventInterpreter()
    _ = interpreter.intents(for: .focused(WindowID(1)), known: nil, displays: [])
    let intents = interpreter.intents(for: .destroyed(WindowID(2)), known: nil, displays: [])
    #expect(intents == [.closed(WindowID(2)), .listsMayHaveChanged])
  }

  /// macOS 27 reports the app's pick before the close (`macos-behaviour.md`, "The focus after a
  /// close").
  @Test func theWindowAFocusJustLeftClosingIsTheFocusedOne() {
    var interpreter = WindowEventInterpreter()
    let first = makeWindow(id: 1)
    _ = interpreter.intents(for: .focused(first.id), known: first, displays: [])
    _ = interpreter.intents(for: .focused(WindowID(2)), known: nil, displays: [])
    let intents = interpreter.intents(for: .destroyed(first.id), known: nil, displays: [])
    #expect(intents.first == .closedWithFocus(Self.focused(first)))
  }

  @Test func theWindowAFocusLeftLongAgoClosingIsJustAClose() {
    var interpreter = WindowEventInterpreter()
    _ = interpreter.intents(for: .focused(WindowID(1)), known: nil, displays: [])
    _ = interpreter.intents(for: .focused(WindowID(2)), known: nil, displays: [])
    interpreter.forgetPreviousFocus()
    let intents = interpreter.intents(for: .destroyed(WindowID(1)), known: nil, displays: [])
    #expect(intents == [.closed(WindowID(1)), .listsMayHaveChanged])
  }

  @Test func tylerdsOwnFocusLeavesNoWindowBehind() {
    var interpreter = WindowEventInterpreter()
    _ = interpreter.intents(for: .focused(WindowID(1)), known: nil, displays: [])
    interpreter.expectFocus(of: WindowID(2))
    _ = interpreter.intents(for: .focused(WindowID(2)), known: nil, displays: [])
    let intents = interpreter.intents(for: .destroyed(WindowID(1)), known: nil, displays: [])
    #expect(intents == [.closed(WindowID(1)), .listsMayHaveChanged])
  }

  /// On macOS 26.7 the app's pick came after tylerd's own focus of the successor: it must still
  /// come from the closed window.
  @Test func everyFocusComesFromTheClosedWindowUntilItIsForgotten() {
    var interpreter = WindowEventInterpreter()
    let first = makeWindow(id: 1)
    _ = interpreter.intents(for: .focused(first.id), known: first, displays: [])
    _ = interpreter.intents(for: .destroyed(first.id), known: nil, displays: [])
    interpreter.expectFocus(of: WindowID(2))
    let echo = interpreter.intents(for: .focused(WindowID(2)), known: nil, displays: [])
    let pick = interpreter.intents(for: .focused(WindowID(3)), known: nil, displays: [])
    #expect(echo.first == .focused(WindowID(2), isEcho: true, from: Self.focused(first)))
    #expect(pick.first == .focused(WindowID(3), isEcho: false, from: Self.focused(first)))
    interpreter.forgetClosedFocus()
    let later = interpreter.intents(for: .focused(WindowID(4)), known: nil, displays: [])
    #expect(later.first == .focused(WindowID(4), isEcho: false, from: Self.unknown(3)))
  }

  /// A quit closes window after window: the one tylerd just asked to focus can go before its
  /// focus arrives.
  @Test func theWindowAskedForClosingWhileACloseIsRememberedIsTheFocusedOne() {
    var interpreter = WindowEventInterpreter()
    let first = makeWindow(id: 1)
    _ = interpreter.intents(for: .focused(first.id), known: first, displays: [])
    _ = interpreter.intents(for: .destroyed(first.id), known: nil, displays: [])
    let second = makeWindow(id: 2)
    interpreter.expectFocus(of: second.id)
    let intents = interpreter.intents(for: .destroyed(second.id), known: second, displays: [])
    #expect(intents.first == .closedWithFocus(Self.focused(second)))
    #expect(interpreter.expectedFocus.isEmpty)
    let pick = interpreter.intents(for: .focused(WindowID(3)), known: nil, displays: [])
    #expect(
      pick.first == .focused(WindowID(3), isEcho: false, from: Self.focused(first)),
      "the first window stays the origin")
  }

  @Test func aWindowAskedForClosingWithNoCloseRememberedIsJustAClose() {
    var interpreter = WindowEventInterpreter()
    _ = interpreter.intents(for: .focused(WindowID(1)), known: nil, displays: [])
    interpreter.expectFocus(of: WindowID(2))
    let intents = interpreter.intents(for: .destroyed(WindowID(2)), known: nil, displays: [])
    #expect(intents == [.closed(WindowID(2)), .listsMayHaveChanged])
  }

  /// An expectation from long ago (#11) says nothing about this close.
  @Test func aStaleExpectedWindowClosingWhileACloseIsRememberedIsJustAClose() {
    var interpreter = WindowEventInterpreter()
    interpreter.expectFocus(of: WindowID(9))
    _ = interpreter.intents(for: .focused(WindowID(1)), known: nil, displays: [])
    _ = interpreter.intents(for: .destroyed(WindowID(1)), known: nil, displays: [])
    let intents = interpreter.intents(for: .destroyed(WindowID(9)), known: nil, displays: [])
    #expect(intents == [.closed(WindowID(9)), .listsMayHaveChanged])
  }

  @Test func aWindowOpenedSinceTheCloseIsNoAnswerToIt() {
    var interpreter = WindowEventInterpreter()
    _ = interpreter.intents(for: .focused(WindowID(1)), known: nil, displays: [])
    _ = interpreter.intents(for: .destroyed(WindowID(1)), known: nil, displays: [])
    let opened = makeWindow(id: 5)
    _ = interpreter.intents(for: .created(opened), known: nil, displays: [])
    let intents = interpreter.intents(for: .focused(opened.id), known: opened, displays: [])
    #expect(intents.first == .focused(opened.id, isEcho: false, from: nil))
  }

  @Test func aRepeatedFocusKeepsTheWindowBeforeIt() {
    var interpreter = WindowEventInterpreter()
    _ = interpreter.intents(for: .focused(WindowID(1)), known: nil, displays: [])
    _ = interpreter.intents(for: .focused(WindowID(2)), known: nil, displays: [])
    _ = interpreter.intents(for: .focused(WindowID(2)), known: nil, displays: [])
    #expect(interpreter.previousFocused?.id == WindowID(1))
  }

  private static func focused(_ window: WindowInfo) -> FocusedWindow {
    FocusedWindow(id: window.id, kind: window.kind, frame: window.frame)
  }

  private static func unknown(_ value: UInt32) -> FocusedWindow {
    FocusedWindow(id: WindowID(value), kind: nil)
  }
}

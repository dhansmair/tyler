import Testing
import TylerCore

@Suite("Parked focus verdict")
struct ParkedFocusVerdictTests {
  private static func window(_ kind: WindowKind?) -> FocusedWindow {
    FocusedWindow(id: WindowID(1), kind: kind)
  }

  @Test func aGoneStandardWindowDeclines() {
    let verdict = ParkedFocusVerdict(
      isParked: true, previous: Self.window(.standard), previousIsGone: true, unmetRequest: nil)
    #expect(verdict == .decline)
  }

  @Test func aWindowStillThereFollows() {
    let verdict = ParkedFocusVerdict(
      isParked: true, previous: Self.window(.standard), previousIsGone: false, unmetRequest: nil)
    #expect(verdict == .follow)
  }

  @Test(arguments: [WindowKind.dialog, .floating, .other, nil])
  func anythingButAStandardWindowFollows(kind: WindowKind?) {
    let verdict = ParkedFocusVerdict(
      isParked: true, previous: Self.window(kind), previousIsGone: true, unmetRequest: nil)
    #expect(verdict == .follow)
  }

  @Test func noPreviousWindowFollows() {
    let verdict = ParkedFocusVerdict(
      isParked: true, previous: nil, previousIsGone: false, unmetRequest: nil)
    #expect(verdict == .follow)
  }

  @Test func aWindowNoLongerParkedFollows() {
    let verdict = ParkedFocusVerdict(
      isParked: false, previous: Self.window(.standard), previousIsGone: true, unmetRequest: nil)
    #expect(verdict == .follow)
  }

  @Test func anUnmetRequestAsksAgain() {
    let request = FocusRequest(window: WindowID(2), isSecondTry: false)
    let verdict = ParkedFocusVerdict(
      isParked: true, previous: Self.window(.standard), previousIsGone: false,
      unmetRequest: request)
    #expect(verdict == .askAgain(WindowID(2)))
  }

  @Test func aSecondTryThatDidntHoldFollows() {
    let request = FocusRequest(window: WindowID(2), isSecondTry: true)
    let verdict = ParkedFocusVerdict(
      isParked: true, previous: nil, previousIsGone: false, unmetRequest: request)
    #expect(verdict == .follow)
  }

  @Test func aWindowThatWentAwayDeclinesBeforeAskingAgain() {
    let request = FocusRequest(window: WindowID(2), isSecondTry: false)
    let verdict = ParkedFocusVerdict(
      isParked: true, previous: Self.window(.standard), previousIsGone: true,
      unmetRequest: request)
    #expect(verdict == .decline)
  }

  @Test func aWindowNoLongerParkedIgnoresTheRequest() {
    let request = FocusRequest(window: WindowID(2), isSecondTry: false)
    let verdict = ParkedFocusVerdict(
      isParked: false, previous: nil, previousIsGone: false, unmetRequest: request)
    #expect(verdict == .follow)
  }
}

import Testing
import TylerCore

@Suite("Parked focus verdict")
struct ParkedFocusVerdictTests {
  private static func window(_ kind: WindowKind?) -> FocusedWindow {
    FocusedWindow(id: WindowID(1), kind: kind)
  }

  @Test func aGoneStandardWindowDeclines() {
    let verdict = ParkedFocusVerdict(
      isParked: true, previous: Self.window(.standard), previousIsGone: true)
    #expect(verdict == .decline)
  }

  @Test func aWindowStillThereFollows() {
    let verdict = ParkedFocusVerdict(
      isParked: true, previous: Self.window(.standard), previousIsGone: false)
    #expect(verdict == .follow)
  }

  @Test(arguments: [WindowKind.dialog, .floating, .other, nil])
  func anythingButAStandardWindowFollows(kind: WindowKind?) {
    let verdict = ParkedFocusVerdict(
      isParked: true, previous: Self.window(kind), previousIsGone: true)
    #expect(verdict == .follow)
  }

  @Test func noPreviousWindowFollows() {
    let verdict = ParkedFocusVerdict(isParked: true, previous: nil, previousIsGone: false)
    #expect(verdict == .follow)
  }

  @Test func aWindowNoLongerParkedFollows() {
    let verdict = ParkedFocusVerdict(
      isParked: false, previous: Self.window(.standard), previousIsGone: true)
    #expect(verdict == .follow)
  }
}

import Testing
import TylerCore

@Suite("Focus after close verdict")
struct FocusAfterCloseVerdictTests {
  private static let closed = FocusedWindow(id: WindowID(1), kind: .standard)

  private static func verdict(
    on windowID: UInt32, closed: FocusedWindow = closed, closedIsGone: Bool = true,
    isAfterClose: Bool = true, isOnClosedDisplay: Bool = true, handedTo: UInt32? = 2,
    isListed: Bool = true
  ) -> FocusAfterCloseVerdict {
    FocusAfterCloseVerdict(
      focused: WindowID(windowID), closed: closed, closedIsGone: closedIsGone,
      situation: .init(
        isAfterClose: isAfterClose, isOnClosedDisplay: isOnClosedDisplay,
        handedTo: handedTo.map(WindowID.init), isListed: isListed))
  }

  @Test func anotherListedWindowAfterACloseIsTakenBack() {
    #expect(Self.verdict(on: 3) == .takeBack)
  }

  @Test func aListedWindowIsTakenBackFromAWorkspaceLeftEmpty() {
    #expect(Self.verdict(on: 3, handedTo: nil) == .takeBack)
  }

  @Test func theWindowTheFocusWasHandedToFollows() {
    #expect(Self.verdict(on: 2) == .follow)
  }

  /// A dialog or a window never tiled: tylerd has no say over them.
  @Test func aWindowOnNoWorkspaceFollows() {
    #expect(Self.verdict(on: 3, isListed: false) == .follow)
  }

  @Test func aWindowStillThereFollows() {
    #expect(Self.verdict(on: 3, closedIsGone: false) == .follow)
  }

  /// A hide, or a quit the window server knows of first: macOS's pick on the same display stands.
  @Test func withNoCloseRememberedTheSameDisplayFollows() {
    #expect(Self.verdict(on: 3, isAfterClose: false) == .follow)
  }

  @Test func withNoCloseRememberedAnotherDisplayIsTakenBack() {
    #expect(Self.verdict(on: 3, isAfterClose: false, isOnClosedDisplay: false) == .takeBack)
  }

  @Test(arguments: [WindowKind.dialog, .floating, .other, nil])
  func anythingButAStandardWindowClosingFollows(kind: WindowKind?) {
    #expect(Self.verdict(on: 3, closed: FocusedWindow(id: WindowID(1), kind: kind)) == .follow)
  }
}

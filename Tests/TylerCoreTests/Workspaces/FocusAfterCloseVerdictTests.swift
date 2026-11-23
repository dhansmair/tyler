import Testing
import TylerCore

@Suite("Focus after close verdict")
struct FocusAfterCloseVerdictTests {
  private static let closed = FocusedWindow(id: WindowID(1), kind: .standard)

  private static func verdict(
    on windowID: UInt32, closed: FocusedWindow? = closed, closedIsGone: Bool = true,
    handedTo: UInt32? = 2, isListed: Bool = true
  ) -> FocusAfterCloseVerdict {
    FocusAfterCloseVerdict(
      focused: WindowID(windowID), closed: closed, closedIsGone: closedIsGone,
      handedTo: handedTo.map(WindowID.init), isListed: isListed)
  }

  @Test func anotherListedWindowIsTakenBack() {
    #expect(Self.verdict(on: 3) == .takeBack)
  }

  @Test func aListedWindowIsTakenBackFromAWorkspaceLeftEmpty() {
    #expect(Self.verdict(on: 3, handedTo: nil) == .takeBack)
  }

  @Test func theWindowTheFocusWasHandedToFollows() {
    #expect(Self.verdict(on: 2) == .follow)
  }

  /// A new window, a dialog or a window never tiled: tylerd has no say over them.
  @Test func aWindowOnNoWorkspaceFollows() {
    #expect(Self.verdict(on: 3, isListed: false) == .follow)
  }

  @Test func aWindowStillThereFollows() {
    #expect(Self.verdict(on: 3, closedIsGone: false) == .follow)
  }

  @Test(arguments: [WindowKind.dialog, .floating, .other, nil])
  func anythingButAStandardWindowClosingFollows(kind: WindowKind?) {
    #expect(Self.verdict(on: 3, closed: FocusedWindow(id: WindowID(1), kind: kind)) == .follow)
  }

  @Test func noWindowBeforeFollows() {
    #expect(Self.verdict(on: 3, closed: nil) == .follow)
  }
}

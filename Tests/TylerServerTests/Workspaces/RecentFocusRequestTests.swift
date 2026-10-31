import Testing
import TylerCore
import TylerTestSupport

@testable import TylerServer

@Suite("Recent focus request")
@MainActor
struct RecentFocusRequestTests {
  private let requests = RecentFocusRequest(remembering: .milliseconds(200), clock: TestClock())

  @Test func aRepeatedRequestIsNotASecondTry() {
    requests.note(WindowID(2))
    requests.note(WindowID(2))
    #expect(requests.request == FocusRequest(window: WindowID(2), isSecondTry: false))
  }

  @Test func aSecondTryIsMarked() {
    requests.note(WindowID(2))
    requests.markSecondTry()
    #expect(requests.request == FocusRequest(window: WindowID(2), isSecondTry: true))
  }

  @Test func aNewRequestStartsOver() {
    requests.note(WindowID(2))
    requests.markSecondTry()
    requests.note(WindowID(3))
    #expect(requests.request == FocusRequest(window: WindowID(3), isSecondTry: false))
  }
}

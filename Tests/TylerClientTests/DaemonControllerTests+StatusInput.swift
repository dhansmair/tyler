import Foundation
import Testing
import TylerCore
import TylerProtocol

@testable import TylerClient

/// `tyler status` lists tylerd's event listeners and says when macOS turned one off, so swipes or
/// focus follows mouse doing nothing can be told apart from a listener that is gone.
@Suite("DaemonController: status and input listeners")
struct DaemonControllerStatusInputTests {
  private func report(_ input: [InputListener]?) -> String? {
    let system = FakeDaemonSystem()
    system.server = .running(FakeDaemonSystem.status(pid: 77, input: input))
    let response = DaemonController(
      system: system, serverPath: FakeDaemonSystem.serverPath, logPath: FakeDaemonSystem.logPath
    ).run(.status)
    guard case .message(let text) = response else { return nil }
    return text
  }

  @Test func statusListsTheListeners() {
    let text = report([
      InputListener(kind: .swipes, isListening: true),
      InputListener(kind: .pointerMoves, isListening: false),
    ])
    #expect(
      text?.hasSuffix(
        """
          access  sees the windows
          input   swipes, pointer moves (refused by macOS)
        """) == true)
  }

  @Test func statusSaysWhenNothingIsListenedTo() {
    #expect(report([])?.hasSuffix("\n  input   none") == true)
  }

  @Test(arguments: [
    (1, "swipes turned off by macOS once (last 2m ago), turned back on"),
    (3, "swipes turned off by macOS 3 times (last 2m ago), turned back on"),
  ])
  func statusSaysHowOftenMacOSTurnedAListenerOff(times: Int, line: String) {
    let swipes = InputListener(
      kind: .swipes, isListening: true, timesTurnedOff: times,
      lastTurnedOff: FakeDaemonSystem.start - 125)
    let text = report([swipes])
    #expect(text?.hasSuffix("\n  input   swipes\n          " + line) == true)
  }

  @Test func statusFromAServerWithoutTheReportLeavesTheLineOut() {
    #expect(report(nil)?.contains("input") == false)
  }
}

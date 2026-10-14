import ApplicationServices
import CoreGraphics
import Testing
import TylerCore
import TylerServer
import TylerTestSupport

@testable import TylerPlatform

@Suite("MacWindowSystem: apps that fail")
@MainActor
struct MacWindowSystemFailuresTests {
  private let harness = WindowSystemHarness()

  private func started() async -> WindowSystemHarness {
    harness.addApp(100, windows: [1, 2])
    harness.addApp(200, windows: [3])
    await harness.start()
    _ = await harness.takeEvents()
    return harness
  }

  @Test(arguments: [
    (AXError.cannotComplete, "its app didn't answer"),
    (AXError.attributeUnsupported, "AX error -25205"),
  ])
  func aRefusalGivesOnlyTheReason(status: AXError, reason: String) {
    #expect(MacWindowSystem.refusal(status) == .refused(reason))
  }

  @Test func aWindowThatClosedUnderUsIsForgotten() async {
    let harness = await started()
    harness.accessibility.removeWindow(1)
    #expect(throws: WindowSystemError.windowGone(WindowID(1))) {
      try harness.windowSystem.focus(WindowID(1))
    }
    #expect(await harness.takeEvents().destroyed == [1])
    #expect(harness.windowSystem.snapshot().map(\.id.rawValue) == [2, 3])
  }

  @Test func anAppThatDidNotAnswerIsSkippedForAWhile() async throws {
    let harness = await started()
    harness.accessibility.answer(.cannotComplete, fromApp: 100)
    #expect(throws: WindowSystemError.refused("its app didn't answer")) {
      try harness.windowSystem.setFrame(.zero, of: WindowID(1))
    }
    harness.accessibility.answer(nil, fromApp: 100)
    harness.accessibility.forgetCalls()

    let skipped = WindowSystemError.refused("its app didn't answer a moment ago")
    #expect(throws: skipped) { try harness.windowSystem.focus(WindowID(2)) }
    #expect(throws: skipped) { try harness.windowSystem.setPosition(.zero, of: WindowID(2)) }
    #expect(throws: skipped) { try harness.windowSystem.setFrame(.zero, of: WindowID(2)) }
    #expect(harness.accessibility.calls(on: 2).isEmpty, "nothing was asked of the app")
    try harness.windowSystem.focus(WindowID(3))
    #expect(harness.accessibility.calls(on: 3).contains(.raise), "another app still answers")
  }

  @Test func anotherFailureLeavesTheAppAlone() async throws {
    let harness = await started()
    harness.accessibility.answer(.attributeUnsupported, from: 1)
    #expect(throws: WindowSystemError.refused("AX error -25205")) {
      try harness.windowSystem.setFrame(.zero, of: WindowID(1))
    }
    try harness.windowSystem.focus(WindowID(2))
  }

  @Test func aWindowNotTrackedIsGone() async {
    let harness = await started()
    #expect(throws: WindowSystemError.windowGone(WindowID(9))) {
      try harness.windowSystem.setFrame(.zero, of: WindowID(9))
    }
    #expect(throws: WindowSystemError.windowGone(WindowID(9))) {
      try harness.windowSystem.close(WindowID(9))
    }
  }
}

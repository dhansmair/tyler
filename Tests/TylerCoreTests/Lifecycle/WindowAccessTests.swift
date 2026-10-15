import Testing

@testable import TylerCore

@Suite("WindowAccess")
struct WindowAccessTests {
  fileprivate static func facts(
    trusted: Bool = true, probe: AccessFacts.Probe = .allowed, locked: Bool = false
  ) -> AccessFacts {
    AccessFacts(isTrusted: trusted, probe: probe, isScreenLocked: locked)
  }

  @Test(arguments: [
    (WindowAccessTests.facts(), WindowAccess.ok),
    (WindowAccessTests.facts(probe: .noAnswer), .ok),
    (WindowAccessTests.facts(trusted: false), .notTrusted),
    (WindowAccessTests.facts(trusted: false, probe: .refused, locked: true), .notTrusted),
    (WindowAccessTests.facts(locked: true), .screenLocked),
    (WindowAccessTests.facts(probe: .refused, locked: true), .screenLocked),
    (WindowAccessTests.facts(probe: .refused), .refused),
  ])
  func beforeStartingTheFactsDecide(facts: AccessFacts, access: WindowAccess) {
    #expect(WindowAccess.beforeStart(facts) == access)
  }

  struct Running: Sendable {
    let onScreen: Set<WindowID>
    let known: Set<WindowID>
    var isAttaching = false

    init(onScreen: [UInt32], known: [UInt32], isAttaching: Bool = false) {
      self.onScreen = Set(onScreen.map(WindowID.init))
      self.known = Set(known.map(WindowID.init))
      self.isAttaching = isAttaching
    }
  }

  @Test(arguments: [
    (Running(onScreen: [1, 2], known: [2, 3]), WindowAccess.ok),
    (Running(onScreen: [], known: []), .ok),
    (Running(onScreen: [], known: [1]), .ok),
    (Running(onScreen: [1, 2], known: [], isAttaching: true), .checking),
    (Running(onScreen: [1, 2], known: [3], isAttaching: true), .checking),
    (Running(onScreen: [1, 2], known: []), .blind),
    (Running(onScreen: [1, 2], known: [3]), .blind),
  ])
  func whileRunningOneWindowSeenOnScreenIsEnough(running: Running, access: WindowAccess) {
    let verdict = WindowAccess.whileRunning(
      onScreen: running.onScreen, known: running.known, isAttaching: running.isAttaching)
    #expect(verdict == access)
  }

  @Test(arguments: [
    (WindowAccess.ok, true), (.screenLocked, true), (.checking, true),
    (.notTrusted, false), (.refused, false), (.blind, false),
  ])
  func onlyWhatTheUserMustFixIsUnhealthy(access: WindowAccess, isHealthy: Bool) {
    #expect(access.isHealthy == isHealthy)
  }
}

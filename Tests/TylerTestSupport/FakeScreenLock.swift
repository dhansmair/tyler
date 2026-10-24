import TylerServer

@MainActor
package final class FakeScreenLock: ScreenLock {
  package var isLocked = false

  package init() {}
}

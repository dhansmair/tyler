import Testing

@testable import TylerPlatform

@Suite("UnresponsiveApps")
struct UnresponsiveAppsTests {
  private let start = ContinuousClock.now

  @Test func anAppThatTimedOutIsSkippedForThePause() {
    var apps = UnresponsiveApps()
    let isNew = apps.noteTimeout(of: 100, at: start)
    #expect(isNew)
    #expect(apps.isSkipped(100, at: start + .seconds(1)))
    #expect(!apps.isSkipped(200, at: start + .seconds(1)))
    #expect(!apps.isSkipped(100, at: start + UnresponsiveApps.pause))
  }

  @Test func anotherTimeoutWhileSkippedIsNotNewButExtendsThePause() {
    var apps = UnresponsiveApps()
    _ = apps.noteTimeout(of: 100, at: start)
    let isNewWhileSkipped = apps.noteTimeout(of: 100, at: start + .seconds(4))
    #expect(!isNewWhileSkipped)
    #expect(apps.isSkipped(100, at: start + .seconds(8)))
    let isNewAfterThePause = apps.noteTimeout(of: 100, at: start + .seconds(20))
    #expect(isNewAfterThePause)
  }

  @Test func anAppThatQuitIsForgotten() {
    var apps = UnresponsiveApps()
    _ = apps.noteTimeout(of: 100, at: start)
    apps.forget(100)
    #expect(!apps.isSkipped(100, at: start))
  }
}

import ApplicationServices
import Testing
import TylerCore

@testable import TylerPlatform

/// Application elements stand in for windows: creating one needs no permission and no app.
@Suite("TrackedWindows")
struct TrackedWindowsTests {
  private let first = AXUIElementCreateApplication(1)
  private let second = AXUIElementCreateApplication(2)

  private func tracking() -> TrackedWindows {
    var windows = TrackedWindows()
    windows.track(first, as: WindowID(10), ownedBy: 100)
    windows.track(second, as: WindowID(20), ownedBy: 200)
    return windows
  }

  @Test func keepsEachWindowsElementAndApp() {
    let windows = tracking()
    #expect(windows.ids == [WindowID(10), WindowID(20)])
    #expect(windows.processID(of: WindowID(20)) == 200)
    let element = windows.element(of: WindowID(10))
    #expect(element != nil && CFEqual(element, first))
    #expect(windows.ids(ownedBy: 100) == [WindowID(10)])
  }

  @Test func findsAWindowByItsElement() {
    #expect(tracking().identify(second) == WindowID(20))
    #expect(tracking().identify(AXUIElementCreateApplication(3)) == nil)
  }

  @Test func forgettingSaysWhetherTheWindowWasTracked() {
    var windows = tracking()
    let wasTracked = windows.forget(WindowID(10))
    let wasTrackedAgain = windows.forget(WindowID(10))
    #expect(wasTracked)
    #expect(!wasTrackedAgain)
    #expect(!windows.contains(WindowID(10)))
    windows.forgetAll()
    #expect(windows.ids.isEmpty)
  }

  @Test func aFrameNeedsAnEarlierRead() {
    var windows = tracking()
    let noted = windows.note(.zero, of: WindowID(10))
    #expect(noted == nil)
  }
}

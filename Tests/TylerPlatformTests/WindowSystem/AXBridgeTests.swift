import ApplicationServices
import CoreGraphics
import Testing
import TylerCore

@testable import TylerPlatform

@Suite("AXBridge")
@MainActor
struct AXBridgeTests {
  private let accessibility = FakeAXClient()
  private let bridge: AXBridge
  private let frame = CGRect(x: 100, y: 50, width: 400, height: 300)

  init() {
    bridge = AXBridge(client: accessibility)
  }

  private func window(buttons: WindowButtons = .all) -> AXUIElement {
    window(subrole: "AXStandardWindow", buttons: buttons)
  }

  private func window(subrole: String?, buttons: WindowButtons = .all) -> AXUIElement {
    accessibility.addWindow(id: 1, frame: frame, subrole: subrole, buttons: buttons, in: 100)
    return accessibility.element(of: 1)
  }

  @Test func aFrameIsSetSizeFirstThenPositionThenSizeAgain() {
    let element = window()
    let target = CGRect(x: 0, y: 0, width: 600, height: 500)
    #expect(bridge.setFrame(target, of: element) == .success)
    #expect(
      accessibility.calls(on: 1) == [.size(target.size), .position(.zero), .size(target.size)])
  }

  @Test func settingAFrameStopsAtTheFirstError() {
    let element = window()
    accessibility.answer(.cannotComplete, from: 1)
    #expect(bridge.setFrame(.zero, of: element) == .cannotComplete)
    #expect(accessibility.calls(on: 1).isEmpty)
  }

  @Test func raisingMakesTheAppFrontmostThenRaisesAndMarksTheWindow() {
    let element = window()
    #expect(bridge.raise(window: element, in: 100) == .success)
    #expect(accessibility.frontmostRequests == [100])
    #expect(accessibility.calls(on: 1) == [.raise, .main, .focused])
  }

  @Test func closingPressesTheCloseButton() {
    let element = window()
    #expect(bridge.close(window: element) == .success)
    #expect(accessibility.calls(on: 1) == [.pressClose])
  }

  @Test func aWindowWithoutACloseButtonCanNotBeClosed() {
    let element = window(buttons: [.minimize])
    #expect(bridge.close(window: element) == .actionUnsupported)
    #expect(accessibility.calls(on: 1).isEmpty)
  }

  @Test func oneReadGetsEveryAttributeAndLeavesOutTheMissingOnes() throws {
    let attributes = try #require(bridge.windowAttributes(of: window(subrole: nil)))
    #expect(attributes.frame == frame)
    #expect(attributes.title == nil)
    #expect(attributes.role == "AXWindow")
    #expect(attributes.subrole == nil)
    #expect(attributes.isMinimized == false)
  }

  @Test func aWindowThatCanNotBeReadHasNoAttributes() {
    let element = window()
    accessibility.answer(.cannotComplete, from: 1)
    #expect(bridge.windowAttributes(of: element) == nil)
    #expect(bridge.frame(of: element) == nil)
  }

  @Test(arguments: [WindowButtons.all, [], [.close], [.minimize, .fullScreen]])
  func theTitleBarButtonsAreThoseTheWindowHas(buttons: WindowButtons) {
    #expect(bridge.windowAttributes(of: window(buttons: buttons))?.buttons == buttons)
  }

  @Test(arguments: [true, false])
  func whetherAWindowWithoutFullScreenCanBeResizedIsRead(isResizable: Bool) {
    accessibility.addWindow(
      id: 1, frame: frame, buttons: [.close, .minimize], isResizable: isResizable, in: 100)
    #expect(
      bridge.windowAttributes(of: accessibility.element(of: 1))?.isResizable == isResizable)
  }

  @Test(arguments: [WindowButtons.all, []])
  func whetherAWindowCanBeResizedIsReadOnlyWhenItsKindDependsOnIt(buttons: WindowButtons) {
    #expect(bridge.windowAttributes(of: window(buttons: buttons))?.isResizable == nil)
    #expect(accessibility.calls(on: 1).isEmpty)
  }

  @Test func aDialogIsNotAskedWhetherItCanBeResized() {
    #expect(
      bridge.windowAttributes(of: window(subrole: "AXDialog", buttons: []))?.isResizable == nil)
    #expect(accessibility.calls(on: 1).isEmpty)
  }

  @Test func observingAWindowTwiceIsHarmless() throws {
    let element = window()
    try bridge.observe(accessibility.createApplication(100), processID: 100) { _, _ in }
    #expect(bridge.observe(window: element, processID: 100).isEmpty)
    #expect(bridge.observe(window: element, processID: 100).isEmpty)
  }

  @Test(arguments: [
    (AXBridge.ObservingFailure.create(.apiDisabled), "observer: AX error -25211"),
    (.register("AXMoved", .cannotComplete), "AXMoved: AX error -25204"),
  ])
  func anObservingFailureNamesItsErrorCode(failure: AXBridge.ObservingFailure, text: String) {
    #expect(String(describing: failure) == text)
  }

  @Test func aWindowIsKnownByItsNumber() {
    let element = window()
    #expect(bridge.windowID(of: element) == WindowID(1))
    accessibility.removeWindow(1)
    #expect(bridge.windowID(of: element) == nil)
  }
}

import Testing

@testable import TylerCore

/// Window 21 is in view and on top, window 11 has the focus, unless a case says otherwise.
@Suite("PointerCheck")
struct PointerCheckTests {
  private static func check(_ change: (inout PointerCheck) -> Void = { _ in }) -> PointerCheck {
    var check = PointerCheck()
    check.topmost = StackedWindow(id: WindowID(21), layer: PointerFocus.normalLayer)
    check.inView = Set(ids(11, 13, 21))
    check.focusedID = WindowID(11)
    change(&check)
    return check
  }

  @Test func aWindowInViewIsGrabbedAndFocused() {
    #expect(Self.check().grab == .window(WindowID(21)))
    #expect(Self.check().focus == .window(WindowID(21)))
  }

  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let change: @Sendable (inout PointerCheck) -> Void
    let grab: PointerRefusal?
    let focus: PointerRefusal?
    var testDescription: String { name }
  }

  @Test(arguments: [
    Case(name: "tiling off", change: { $0.isTiling = false }, grab: .tilingOff, focus: .tilingOff),
    Case(name: "a slide", change: { $0.isIdle = false }, grab: .busy, focus: .busy),
    Case(
      name: "outside the displays", change: { $0.isInsideDisplay = false },
      grab: .outsideDisplays, focus: .outsideDisplays),
    Case(
      name: "nothing there", change: { $0.topmost = nil }, grab: .nothingThere, focus: .nothingThere
    ),
    Case(
      name: "a menu on top",
      change: { $0.topmost = StackedWindow(id: WindowID(21), layer: 101) },
      grab: .notANormalWindow, focus: .notANormalWindow),
    Case(
      name: "a parked window",
      change: { $0.topmost = StackedWindow(id: WindowID(12), layer: 0) },
      grab: .notInView, focus: .notInView),
    Case(
      name: "focus follows mouse off", change: { $0.focusFollows = false }, grab: nil,
      focus: .focusFollowsOff),
    Case(name: "a button held", change: { $0.isButtonHeld = true }, grab: nil, focus: .buttonHeld),
    Case(name: "a menu open", change: { $0.isMenuOpen = true }, grab: nil, focus: .menuOpen),
    Case(
      name: "the focused window", change: { $0.focusedID = WindowID(21) }, grab: nil,
      focus: .alreadyFocused),
  ])
  func eachReasonIsReported(_ test: Case) {
    let check = Self.check(test.change)
    #expect(check.grab == (test.grab.map { .refused($0) } ?? .window(WindowID(21))))
    #expect(check.focus == (test.focus.map { .refused($0) } ?? .window(WindowID(21))))
  }

  @Test func theFirstReasonCounts() {
    let check = Self.check {
      $0.isTiling = false
      $0.topmost = nil
    }
    #expect(check.grab == .refused(.tilingOff))
  }

  @Test(arguments: PointerRefusal.allCases)
  func everyReasonIsExplained(refusal: PointerRefusal) {
    #expect(!refusal.explanation.isEmpty)
  }

  private static var overAnEmptyWorkspace: PointerCheck {
    var check = PointerCheck()
    check.isWorkspaceEmpty = true
    return check
  }

  @Test func aRestOverAnEmptyWorkspaceFocusesIt() {
    #expect(Self.overAnEmptyWorkspace.focus == .emptyWorkspace)
  }

  @Test func aRestOverAWorkspaceWithWindowsDoesNot() {
    #expect(PointerCheck().focus == .refused(.nothingThere))
  }

  @Test func aRestOverAnyWindowDoesNot() {
    var check = Self.overAnEmptyWorkspace
    check.topmost = StackedWindow(id: WindowID(1), layer: 25)
    #expect(check.focus != .emptyWorkspace)
  }

  @Test(arguments: [(true, false), (false, true)])
  func aRestDoesNotWhenCoveredOrWithAFloatFocused(isCovered: Bool, isFloatFocused: Bool) {
    var check = Self.overAnEmptyWorkspace
    check.isCovered = isCovered
    check.isFocusOffWorkspaces = isFloatFocused
    #expect(check.focus == .refused(.nothingThere))
  }

  @Test func aRestDoesNotWithoutWhatFocusNeeds() {
    let required: [WritableKeyPath<PointerCheck, Bool>] = [
      \.focusFollows, \.isTiling, \.isIdle, \.isInsideDisplay,
    ]
    for path in required {
      var check = Self.overAnEmptyWorkspace
      check[keyPath: path] = false
      #expect(check.focus != .emptyWorkspace, "with \(path) false")
    }
  }

  @Test func aRestDoesNotWithAButtonHeldOrAMenuOpen() {
    let blocking: [WritableKeyPath<PointerCheck, Bool>] = [\.isButtonHeld, \.isMenuOpen]
    for path in blocking {
      var check = Self.overAnEmptyWorkspace
      check[keyPath: path] = true
      #expect(check.focus != .emptyWorkspace, "with \(path) true")
    }
  }
}

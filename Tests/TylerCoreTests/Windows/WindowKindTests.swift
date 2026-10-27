import Testing

@testable import TylerCore

@Suite("WindowKind")
struct WindowKindTests {
  struct Case: Sendable {
    let role: String?
    let subrole: String?
    var buttons: WindowButtons = .all
    var isResizable: Bool?
    let expected: WindowKind
  }

  @Test(
    arguments: [
      Case(role: "AXWindow", subrole: "AXStandardWindow", expected: .standard),
      Case(role: "AXWindow", subrole: "AXDialog", buttons: [.close, .minimize], expected: .dialog),
      // TextEdit's untitled documents before the app was first active.
      Case(role: "AXWindow", subrole: "AXDialog", expected: .standard),
      // TextEdit's Open panel.
      Case(role: "AXWindow", subrole: "AXStandardWindow", buttons: [], expected: .dialog),
      // Outlook's reminder popup.
      Case(
        role: "AXWindow", subrole: "AXStandardWindow", buttons: [.close, .minimize],
        isResizable: false, expected: .dialog),
      // A document whose green button only zooms.
      Case(
        role: "AXWindow", subrole: "AXStandardWindow", buttons: [.close, .minimize],
        isResizable: true, expected: .standard),
      Case(
        role: "AXWindow", subrole: "AXStandardWindow", buttons: [.close, .minimize],
        expected: .standard),
      Case(role: "AXWindow", subrole: "AXStandardWindow", buttons: [.close], expected: .standard),
      Case(
        role: "AXWindow", subrole: "AXStandardWindow", isResizable: false, expected: .standard),
      Case(role: "AXWindow", subrole: "AXSystemDialog", expected: .dialog),
      Case(role: "AXSheet", subrole: nil, expected: .dialog),
      Case(role: "AXWindow", subrole: "AXFloatingWindow", expected: .floating),
      Case(role: "AXWindow", subrole: "AXSystemFloatingWindow", expected: .floating),
      Case(role: "AXWindow", subrole: "AXUnknown", expected: .other),
      Case(role: "AXWindow", subrole: nil, expected: .other),
      Case(role: nil, subrole: nil, expected: .other),
      Case(role: "AXButton", subrole: "AXStandardWindow", expected: .other),
    ]
  )
  func classifiesRoleAndSubrole(testCase: Case) {
    #expect(
      WindowKind.classify(
        role: testCase.role, subrole: testCase.subrole, buttons: testCase.buttons,
        isResizable: testCase.isResizable)
        == testCase.expected)
  }
}

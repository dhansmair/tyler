import Testing

@testable import TylerCore

@Suite("WindowKind")
struct WindowKindTests {
  struct Case: Sendable {
    let role: String?
    let subrole: String?
    let expected: WindowKind
  }

  @Test(
    arguments: [
      Case(role: "AXWindow", subrole: "AXStandardWindow", expected: .standard),
      Case(role: "AXWindow", subrole: "AXDialog", expected: .dialog),
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
      WindowKind.classify(role: testCase.role, subrole: testCase.subrole) == testCase.expected)
  }
}

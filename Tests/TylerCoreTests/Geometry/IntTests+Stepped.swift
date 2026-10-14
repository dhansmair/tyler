import Testing

@testable import TylerCore

@Suite("Int: stepping in a ring")
struct IntSteppedTests {
  @Test(arguments: [(0, -1, 2), (2, 1, 0), (1, 1, 2), (0, 4, 1)])
  func steppingWrapsAroundBothEnds(index: Int, offset: Int, expected: Int) {
    #expect(index.stepped(by: offset, wrappingAt: 3) == expected)
  }
}

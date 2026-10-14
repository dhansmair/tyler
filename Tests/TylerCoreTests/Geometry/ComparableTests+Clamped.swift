import Testing

@testable import TylerCore

@Suite("Comparable: clamping")
struct ComparableClampedTests {
  @Test func clampingMovesAValueIntoTheRange() {
    #expect((-0.5).clamped(to: 0...1) == 0)
    #expect(0.25.clamped(to: 0...1) == 0.25)
    #expect(7.clamped(to: 1...4) == 4)
  }
}

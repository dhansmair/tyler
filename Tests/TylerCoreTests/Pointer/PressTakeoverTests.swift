import Testing

@testable import TylerCore

@Suite("PressTakeover")
struct PressTakeoverTests {
  enum Change: Sendable {
    case keys(ModifierKeys)
    case gap(Bool)
    case gesture(Bool)
  }

  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    var modifier = ModifierKeys.option
    var takesGaps = true
    let changes: [Change]
    /// `needsTap` after each change.
    let needs: [Bool]

    var testDescription: String { name }
  }

  @Test(arguments: [
    Case(
      name: "the modifier alone arms it", changes: [.keys(.option), .keys([])],
      needs: [true, false]),
    Case(
      name: "the modifier with another key doesn't", changes: [.keys([.option, .shift])],
      needs: [false]),
    Case(
      name: "another key added to the modifier disarms it",
      changes: [.keys(.option), .keys([.option, .command]), .keys(.option)],
      needs: [true, false, true]),
    Case(
      name: "no modifier configured, no keys arm it", modifier: [], changes: [.keys([])],
      needs: [false]),
    Case(name: "a gap arms it", changes: [.gap(true), .gap(false)], needs: [true, false]),
    Case(name: "gaps off, a gap doesn't", takesGaps: false, changes: [.gap(true)], needs: [false]),
    Case(
      name: "a gesture keeps it after the keys come up",
      changes: [.keys(.option), .gesture(true), .keys([]), .gesture(false)],
      needs: [true, true, true, false]),
    Case(
      name: "a gap drag keeps it after the pointer leaves the gap",
      changes: [.gap(true), .gesture(true), .gap(false), .gesture(false)],
      needs: [true, true, true, false]),
    Case(
      name: "the modifier still held after a gesture keeps it",
      changes: [.keys(.option), .gesture(true), .gesture(false)], needs: [true, true, true]),
  ])
  func needsTheTap(_ test: Case) {
    var takeover = PressTakeover(modifier: test.modifier, takesGaps: test.takesGaps)
    var needs: [Bool] = []
    for change in test.changes {
      let before = takeover.needsTap
      let changed: Bool
      switch change {
      case .keys(let keys): changed = takeover.keysChanged(to: keys)
      case .gap(let isOverGap): changed = takeover.gapHovered(isOverGap)
      case .gesture(let isActive): changed = takeover.gestureChanged(isActive: isActive)
      }
      #expect(changed == (takeover.needsTap != before), "reports exactly the flips")
      needs.append(takeover.needsTap)
    }
    #expect(needs == test.needs)
  }

  @Test func atRestItNeedsNoTap() {
    #expect(PressTakeover(modifier: .option, takesGaps: true).needsTap == false)
  }
}

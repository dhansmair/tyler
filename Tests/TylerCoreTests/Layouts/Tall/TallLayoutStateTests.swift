import Foundation
import Testing

@testable import TylerCore

@Suite("TallLayoutState")
struct TallLayoutStateTests {
  @Test func aClosingMainShrinksTheMainSection() {
    var state = TallLayoutState(mainCount: 2)
    state.remove(WindowID(2), from: ids(1, 2, 3))
    #expect(state.mainCount == 1)
  }

  @Test func aClosingStackedWindowLeavesTheMainSection() {
    var state = TallLayoutState(mainCount: 2)
    state.remove(WindowID(3), from: ids(1, 2, 3))
    #expect(state.mainCount == 2)
  }

  @Test func theLastMainClosingLeavesOneMain() {
    var state = TallLayoutState()
    state.remove(WindowID(1), from: ids(1, 2))
    #expect(state.mainCount == 1)
  }

  @Test func theMainCountComesBackFromAFile() throws {
    let state = TallLayoutState(mainRatio: 0.6, mainCount: 3)
    let decoded = try JSONDecoder().decode(
      TallLayoutState.self, from: try JSONEncoder().encode(state))
    #expect(decoded == state)
  }

  @Test func aFileFromBeforeSeveralMainsGivesOne() throws {
    let json = Data(#"{"mainRatio": 0.6, "rowWeights": []}"#.utf8)
    let decoded = try JSONDecoder().decode(TallLayoutState.self, from: json)
    #expect(decoded == TallLayoutState(mainRatio: 0.6))
  }
}

import Testing

@testable import TylerCore

@Suite("ScrollDirection")
struct ScrollDirectionTests {
  @Test(arguments: [(-0.5, ScrollDirection?.some(.next)), (0.5, .prev), (0, nil)])
  func anOffsetRevealsTheNeighbourOnTheOtherSide(offset: Double, side: ScrollDirection?) {
    #expect(ScrollDirection(revealedBy: offset) == side)
  }
}

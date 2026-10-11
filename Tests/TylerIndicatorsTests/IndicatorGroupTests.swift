import Testing
import TylerCore

@testable import TylerIndicators

@Suite("Indicator group")
@MainActor
struct IndicatorGroupTests {
  @Test func everyMemberIsShownEverySnapshot() {
    let members = [RecordingIndicator(), RecordingIndicator()]
    let group = IndicatorGroup(members)
    group.show(snapshot(current: 0))
    group.show(snapshot(current: 2))
    for member in members {
      #expect(member.shown.map(\.row.currentIndex) == [0, 2])
    }
  }
}

@MainActor
private final class RecordingIndicator: Indicator {
  private(set) var shown: [IndicatorSnapshot] = []

  func show(_ snapshot: IndicatorSnapshot) { shown.append(snapshot) }
}

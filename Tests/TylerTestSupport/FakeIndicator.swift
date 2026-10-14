import TylerProtocol

@testable import TylerServer

/// Records every snapshot the manager shows.
@MainActor
package final class FakeIndicator: Indicator {
  package private(set) var shown: [IndicatorSnapshot] = []

  package init() {}

  package func show(_ snapshot: IndicatorSnapshot) { shown.append(snapshot) }
}

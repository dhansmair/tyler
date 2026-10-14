import TylerProtocol

/// Several indicators shown as one: every snapshot goes to each of them, in order.
@MainActor
package final class IndicatorGroup: Indicator {
  private let members: [any Indicator]

  package init(_ members: [any Indicator]) {
    self.members = members
  }

  package func show(_ snapshot: IndicatorSnapshot) {
    for member in members {
      member.show(snapshot)
    }
  }
}

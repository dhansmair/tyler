import TylerCore

/// Several indicators shown as one: every snapshot goes to each of them, in order.
@MainActor
public final class IndicatorGroup: Indicator {
  private let members: [any Indicator]

  public init(_ members: [any Indicator]) {
    self.members = members
  }

  public func show(_ snapshot: IndicatorSnapshot) {
    for member in members {
      member.show(snapshot)
    }
  }
}

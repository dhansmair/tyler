/// What keeps a member of a workspace out of its layout. The member keeps its place in the list.
package struct MemberFlags: OptionSet, Hashable, Sendable {
  package let rawValue: UInt8

  package init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  package static let hidden = MemberFlags(rawValue: 1 << 0)
}

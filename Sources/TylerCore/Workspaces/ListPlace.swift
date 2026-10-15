/// A place in a workspace's list for a window to go: the index it will have there, and in
/// `tall`, whether it is in the master section there.
package struct ListPlace: Equatable, Sendable {
  package let index: Int
  package let isInMainSection: Bool

  package init(index: Int, isInMainSection: Bool = false) {
    self.index = index
    self.isInMainSection = isInMainSection
  }
}

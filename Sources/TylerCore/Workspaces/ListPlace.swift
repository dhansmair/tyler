/// A place in a workspace's list for a window to go: the index it will have there.
package struct ListPlace: Equatable, Sendable {
  package let index: Int

  package init(index: Int) {
    self.index = index
  }
}

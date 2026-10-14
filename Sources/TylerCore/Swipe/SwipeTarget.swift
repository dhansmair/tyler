/// What a trackpad swipe moves: the row of workspaces, or the view of a scrolling layout.
package enum SwipeTarget: Equatable, Sendable {
  /// The neighbouring workspaces, both worked out when the swipe began (frames read later would
  /// be mid-slide). With two workspaces both sides bring in the same one, from opposite edges.
  case workspaceRow(prev: SlidePlan, next: SlidePlan)
  /// The current workspace's scrolling layout, with every view it can rest at.
  case view(ViewScroll)
}

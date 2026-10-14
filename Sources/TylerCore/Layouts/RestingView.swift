import CoreGraphics

package struct RestingView: Equatable, Sendable {
  package let firstVisible: Int
  /// How far this view is scrolled from the first one, in points.
  package let offset: CGFloat
}

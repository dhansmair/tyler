import CoreGraphics

extension Track {
  /// The size a window has at the start of a track and the one it has at the end.
  package struct Sizes: Equatable, Sendable {
    package let start: CGSize
    package let end: CGSize

    package init(start: CGSize, end: CGSize) {
      self.start = start
      self.end = end
    }
  }
}

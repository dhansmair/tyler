import CoreGraphics

/// One write of a window's frame to its app.
package enum FrameWrite: Equatable, Sendable {
  case position(CGPoint)
  case size(CGSize)

  /// At most two writes from `current` to `target`, ordered so that the window never reaches past
  /// both frames on the way: moved first when it grows, resized first when it shrinks. macOS stops
  /// a window that grows at the edge of its display, so the other order could cut it short.
  /// `nil` when it grows one way and shrinks the other, and no order is safe.
  package static func inPassing(from current: CGRect, to target: CGRect) -> [FrameWrite]? {
    let grows = target.width > current.width || target.height > current.height
    let shrinks = target.width < current.width || target.height < current.height
    guard !(grows && shrinks) else { return nil }
    let move: [FrameWrite] = target.origin == current.origin ? [] : [.position(target.origin)]
    let resize: [FrameWrite] = target.size == current.size ? [] : [.size(target.size)]
    return grows ? move + resize : resize + move
  }
}

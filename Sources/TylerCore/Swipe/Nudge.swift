import CoreGraphics

/// One step of a slide: a window moved without being resized.
package struct Nudge: Equatable, Sendable {
  package let id: WindowID
  package let origin: CGPoint

  package init(id: WindowID, origin: CGPoint) {
    self.id = id
    self.origin = origin
  }
}

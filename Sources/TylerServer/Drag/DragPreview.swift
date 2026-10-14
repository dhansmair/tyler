import CoreGraphics
import TylerCore

/// The windows a drag's preview is moving to where a drop would put them, and the task moving
/// them.
struct DragPreview {
  let id: Int
  let task: Task<Void, Never>
  let finals: [Placement]
  /// Where each window was last put, for a new preview that takes over before this one is done.
  var frames: [WindowID: CGRect]
}

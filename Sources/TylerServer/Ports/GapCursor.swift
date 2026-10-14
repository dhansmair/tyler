import CoreGraphics

/// The resize cursor over the gap the pointer is in, showing that dragging it resizes. The real
/// one is a window of tylerd's over the gap that sets the cursor (`TylerPlatform.MacGapCursor`);
/// tests use a fake.
@MainActor
package protocol GapCursor: AnyObject {
  /// Shows the resize cursor over `area`, in Accessibility coordinates: across a gap taller than
  /// wide, up and down otherwise.
  func show(over area: CGRect)
  func hide()
}

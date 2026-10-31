import CoreGraphics

/// The brief notice naming the layout just chosen. The real one is a window of tylerd's that
/// fades out by itself (`TylerPlatform.MacLayoutNotice`); tests use a fake.
@MainActor
package protocol LayoutNotice: AnyObject {
  /// Shows `name` in the middle of `area`, in Accessibility coordinates, in place of any notice
  /// still showing.
  func show(_ name: String, in area: CGRect)
}

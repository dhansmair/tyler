import CoreGraphics
import TylerCore

extension ModifierKeys {
  /// The modifier keys an event was made with; other flags (Caps Lock, Fn) are left out.
  init(flags: CGEventFlags) {
    self = []
    if flags.contains(.maskAlternate) { insert(.option) }
    if flags.contains(.maskControl) { insert(.control) }
    if flags.contains(.maskCommand) { insert(.command) }
    if flags.contains(.maskShift) { insert(.shift) }
  }
}

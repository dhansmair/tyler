import AppKit
import TylerCore
import TylerRuntime

/// Watches the modifier keys go down and up through a listen-only event tap on `flagsChanged`,
/// so the mouse button interceptor's active tap can exist only while they are held. A listen-only
/// tap is safe when Accessibility is taken away; an active one is not (see "Events and taps" in
/// `devdocs/macos-behaviour.md`).
@MainActor
final class ModifierKeyListener {
  private static let log = TylerLog(category: "pointer")

  private let report: (ModifierKeys) -> Void
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?

  /// Starts watching; `report` gets the keys held after each change. Without permission to tap
  /// events, it logs that and stays silent.
  init(report: @escaping (ModifierKeys) -> Void) {
    self.report = report
    let mask = CGEventMask(1) << CGEventMask(CGEventType.flagsChanged.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
        eventsOfInterest: mask, callback: modifierKeyCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      Self.log.error("modifier key listener refused - moving windows with the modifier is off")
      return
    }
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    // On the main run loop, so the callback runs on the main thread.
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    self.tap = tap
    self.source = source
  }

  /// The keys held right now, for a listener that starts with keys already down.
  static var keysHeld: ModifierKeys {
    ModifierKeys(flags: CGEventSource.flagsState(.combinedSessionState))
  }

  /// `false` when macOS refused the tap.
  var isListening: Bool { tap != nil }

  /// Stops watching. The tap holds an unretained pointer to this object, so this must run before
  /// it goes away.
  func invalidate() {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let tap { CFMachPortInvalidate(tap) }
    source = nil
    tap = nil
  }

  fileprivate func handle(_ keys: ModifierKeys) {
    report(keys)
  }

  /// Turns the tap back on if macOS turned it off, and says whether it had. A change missed
  /// meanwhile is read from the keys held now.
  func turnBackOnIfOff() -> Bool {
    guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return false }
    CGEvent.tapEnable(tap: tap, enable: true)
    report(Self.keysHeld)
    return true
  }
}

private let modifierKeyCallback: CGEventTapCallBack = { _, type, event, userInfo in
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  // Only Sendable values cross into the main actor: the keys, and the object's address.
  let address = UInt(bitPattern: userInfo)
  let keys: ModifierKeys? = type == .flagsChanged ? ModifierKeys(flags: event.flags) : nil
  // The tap's run loop source is on the main run loop, so this runs on the main thread.
  MainActor.assumeIsolated {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
    let listener = Unmanaged<ModifierKeyListener>.fromOpaque(pointer).takeUnretainedValue()
    if let keys { listener.handle(keys) }
  }
  return Unmanaged.passUnretained(event)
}

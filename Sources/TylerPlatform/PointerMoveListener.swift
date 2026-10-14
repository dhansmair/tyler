import AppKit
import TylerRuntime

/// Watches the pointer move through a listen-only event tap on `mouseMoved`. A global `NSEvent`
/// monitor saw none of the moves posted in the spike, while the tap saw them all (measured on
/// macOS 26.7; see `devdocs/macos-behaviour.md`). Moves with a button held are drags, a
/// different event type, so the tap is silent during a drag.
@MainActor
final class PointerMoveListener {
  private static let log = TylerLog(category: "pointer")

  private let report: (CGPoint) -> Void
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?

  /// Starts watching; `report` gets each new pointer location, in Accessibility coordinates.
  /// Without permission to tap events, it logs that and stays silent.
  init(report: @escaping (CGPoint) -> Void) {
    self.report = report
    let mask = CGEventMask(1) << CGEventMask(CGEventType.mouseMoved.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
        eventsOfInterest: mask, callback: pointerMoveCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      Self.log.error("pointer move listener refused - focus follows mouse is off")
      return
    }
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    // On the main run loop, so the callback runs on the main thread.
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    self.tap = tap
    self.source = source
  }

  /// Stops watching. The tap holds an unretained pointer to this object, so this must run before
  /// it goes away.
  func invalidate() {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let tap { CFMachPortInvalidate(tap) }
    source = nil
    tap = nil
  }

  fileprivate func handle(_ location: CGPoint) {
    report(location)
  }

  /// macOS turns a tap off when its callback is slow; turn it back on.
  fileprivate func turnBackOn() {
    if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
  }
}

private let pointerMoveCallback: CGEventTapCallBack = { _, type, event, userInfo in
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  // Only Sendable values cross into the main actor: the location, and the object's address.
  let address = UInt(bitPattern: userInfo)
  let isTurnedOff = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
  // Event locations are global display coordinates with a top-left origin: the same as
  // Accessibility's.
  let location: CGPoint? = type == .mouseMoved ? event.location : nil
  // The tap's run loop source is on the main run loop, so this runs on the main thread.
  MainActor.assumeIsolated {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
    let tap = Unmanaged<PointerMoveListener>.fromOpaque(pointer).takeUnretainedValue()
    if isTurnedOff { tap.turnBackOn() }
    if let location { tap.handle(location) }
  }
  return Unmanaged.passUnretained(event)
}

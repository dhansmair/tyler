// `pointer`: what focus follows mouse would see. Each time the pointer comes to rest, it prints the
// topmost on-screen window under it (number, layer, owner) and every window above the normal layer
// that is on screen, such as open menus, with how long the window list took.

import AppKit
import CoreGraphics

/// One entry of the on-screen window list.
private struct ListedWindow {
  let number: Int
  let layer: Int
  let owner: String
  let name: String
  let frame: CGRect

  init?(_ entry: [String: Any]) {
    guard let number = entry[kCGWindowNumber as String] as? Int,
      let layer = entry[kCGWindowLayer as String] as? Int
    else { return nil }
    self.number = number
    self.layer = layer
    owner = entry[kCGWindowOwnerName as String] as? String ?? "?"
    name = entry[kCGWindowName as String] as? String ?? ""
    let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    frame = CGRect(
      x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0,
      height: bounds["Height"] ?? 0)
  }

  var summary: String { "\(number) layer \(layer) \(owner) \"\(name)\" \(format(frame))" }
}

/// Counts the moves since the last rest and prints what is under the pointer once it rests.
@MainActor
private final class PointerProbe {
  let rest: TimeInterval
  var moves = 0
  var timer: Timer?

  init(rest: TimeInterval) { self.rest = rest }

  func moved() {
    moves += 1
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: rest, repeats: false) { _ in
      MainActor.assumeIsolated { self.rested() }
    }
  }

  func rested() {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let mouse = NSEvent.mouseLocation
    let location = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
    let start = Date()
    let options: CGWindowListOption = [.optionOnScreenOnly]
    let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    let elapsed = Date().timeIntervalSince(start) * 1000
    let windows = list.compactMap(ListedWindow.init)
    let topmost = windows.first { $0.frame.contains(location) }
    print(
      String(
        format: "rest at %@ after %d moves, %d windows listed in %.2f ms", format(location), moves,
        windows.count, elapsed))
    print("  under the pointer: \(topmost?.summary ?? "nothing")")
    // tylerd's MacWindowStacking skips the overlays that cover a whole display (the Dock's,
    // Notification Centre's).
    let seen = windows.first {
      $0.frame.contains(location) && !isOverlay(layer: $0.layer, frame: $0.frame)
    }
    print("  tylerd sees: \(seen?.summary ?? "nothing")")
    for window in windows where window.layer > 0 && window.layer != 25 {
      print("  above normal: \(window.summary)")
    }
    moves = 0
  }
}

/// `pointer <seconds> [rest-ms]`: listens for `seconds`, reporting each rest of `rest-ms`
/// (default 100).
@MainActor
func pointer(_ arguments: [String]) throws(UsageError) {
  guard (1...2).contains(arguments.count), let seconds = Double(arguments[0]), seconds > 0,
    let restMilliseconds = Double(arguments.count == 2 ? arguments[1] : "100")
  else {
    throw UsageError("pointer <seconds> [rest-ms]")
  }
  _ = NSApplication.shared
  setlinebuf(stdout)  // so a log written to a file can be read while it runs
  let probe = PointerProbe(rest: restMilliseconds / 1000)
  // A listen-only tap, as tylerd's PointerMoveListener: a global NSEvent monitor missed the moves in the
  // spike. The tap's source is on the main run loop, so the callback runs on the main thread.
  let mask = CGEventMask(1) << CGEventMask(CGEventType.mouseMoved.rawValue)
  let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
    eventsOfInterest: mask,
    callback: { _, type, event, refcon in
      if type == .mouseMoved, let refcon {
        let address = UInt(bitPattern: refcon)
        MainActor.assumeIsolated {
          guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
          Unmanaged<PointerProbe>.fromOpaque(pointer).takeUnretainedValue().moved()
        }
      }
      return Unmanaged.passUnretained(event)
    },
    userInfo: Unmanaged.passUnretained(probe).toOpaque())
  guard let tap else { throw UsageError("the event tap was refused (missing permission?)") }
  CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
  CGEvent.tapEnable(tap: tap, enable: true)
  print("listening for \(Int(seconds)) s: move the pointer, rest it over windows, open menus")
  RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
  CFMachPortInvalidate(tap)
}

// `display-events`: logs what macOS reports while displays come and go (plugged, unplugged, lid
// closed, sleep and wake, rearranged), and where the windows are once things have settled. This is
// what tylerd reacts to when displays change.

import AppKit
import CoreGraphics

/// The events seen so far, and a timer that dumps the displays and windows once they stop.
@MainActor
private final class DisplayEventLog {
  let start = Date()
  let settle: TimeInterval
  private var settleTimer: Timer?

  init(settle: TimeInterval) { self.settle = settle }

  func log(_ message: String) {
    print(String(format: "%8.3f  ", Date().timeIntervalSince(start)) + message)
    settleTimer?.invalidate()
    settleTimer = Timer.scheduledTimer(withTimeInterval: settle, repeats: false) { _ in
      MainActor.assumeIsolated { self.dumpState() }
    }
  }

  /// The displays as tyler would number them, and every window with the display it is on.
  func dumpState() {
    print(String(format: "%8.3f  quiet for %.1f s; now:", Date().timeIntervalSince(start), settle))
    let all = Display.all()
    for display in all {
      let edge = display.parkingEdge(among: all).map { "parks \($0)" } ?? "no free edge"
      print(
        "          display \(display.number) \(display.name): id \(display.id), uuid \(display.uuid),"
          + " frame \(format(display.frame)), visible \(format(display.visible)), \(edge)")
    }
    for (windowID, window) in Accessibility.windows().sorted(by: { $0.key < $1.key }) {
      guard let origin = Accessibility.origin(of: window), let size = Accessibility.size(of: window)
      else { continue }
      let frame = CGRect(origin: origin, size: size)
      let title = Accessibility.value(kAXTitleAttribute, of: window) as? String ?? ""
      let display = all.max { overlap($0, frame) < overlap($1, frame) }
      let number = display.map { overlap($0, frame) > 0 ? "\($0.number)" : "-" } ?? "-"
      print("          window \(windowID) on \(number)  \(format(frame))  \(title.prefix(40))")
    }
  }

  private func overlap(_ display: Display, _ frame: CGRect) -> CGFloat {
    let shared = display.frame.intersection(frame)
    return shared.isNull ? 0 : shared.width * shared.height
  }
}

private func describe(_ flags: CGDisplayChangeSummaryFlags) -> String {
  let names: [(CGDisplayChangeSummaryFlags, String)] = [
    (.beginConfigurationFlag, "begin"), (.movedFlag, "moved"), (.setMainFlag, "setMain"),
    (.setModeFlag, "setMode"), (.addFlag, "add"), (.removeFlag, "remove"),
    (.enabledFlag, "enabled"), (.disabledFlag, "disabled"), (.mirrorFlag, "mirror"),
    (.unMirrorFlag, "unMirror"), (.desktopShapeChangedFlag, "desktopShape"),
  ]
  let present = names.filter { flags.contains($0.0) }.map(\.1)
  return present.isEmpty ? "none" : present.joined(separator: ",")
}

/// `display-events <seconds> [settle]`: logs display events for `seconds`, and the displays and
/// windows each time no event has arrived for `settle` seconds (default 1).
@MainActor
func displayEvents(_ arguments: [String]) throws(UsageError) {
  guard (1...2).contains(arguments.count), let seconds = Double(arguments[0]), seconds > 0,
    let settle = arguments.count == 2 ? Double(arguments[1]) : 1
  else { throw UsageError("display-events <seconds> [settle]") }
  // Line by line, so a log written to a file can be read while it runs.
  setvbuf(stdout, nil, _IOLBF, 0)
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  app.finishLaunching()
  let log = DisplayEventLog(settle: settle)

  let callback: CGDisplayReconfigurationCallBack = { displayID, flags, userInfo in
    guard let userInfo else { return }
    let log = Unmanaged<DisplayEventLog>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated {
      log.log("reconfiguration: display \(displayID) [\(describe(flags))]")
    }
  }
  CGDisplayRegisterReconfigurationCallback(callback, Unmanaged.passUnretained(log).toOpaque())

  var observers: [(NotificationCenter, NSObjectProtocol)] = []
  let appNames: [Notification.Name] = [NSApplication.didChangeScreenParametersNotification]
  let workspaceNames: [Notification.Name] = [
    NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
    NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
    NSWorkspace.activeSpaceDidChangeNotification,
  ]
  for (center, names) in [
    (NotificationCenter.default, appNames), (NSWorkspace.shared.notificationCenter, workspaceNames),
  ] {
    for name in names {
      let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { log.log("notification: \(name.rawValue)") }
      }
      observers.append((center, observer))
    }
  }

  print("logging for \(Int(seconds)) s; plug, unplug, close the lid, sleep, rearrange")
  log.dumpState()
  // Pump AppKit events too: the screen-parameters notification comes through the event loop.
  let end = Date(timeIntervalSinceNow: seconds)
  while Date() < end {
    let until = min(end, Date(timeIntervalSinceNow: 0.5))
    if let event = app.nextEvent(matching: .any, until: until, inMode: .default, dequeue: true) {
      app.sendEvent(event)
    }
  }
  CGDisplayRemoveReconfigurationCallback(callback, Unmanaged.passUnretained(log).toOpaque())
  for (center, observer) in observers { center.removeObserver(observer) }
  print("done")
}

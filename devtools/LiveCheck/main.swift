// Checks tyler's assumptions against real windows. Run it through `devtools/live-check`, which
// compiles this directory into .build on first use. Needs Accessibility permission for the terminal (the
// same grant tylerd uses). Every command that moves a window puts it back where it was.

import AppKit
import ApplicationServices

// Private but long-standing API that maps an Accessibility element to its `CGWindowID`.
@_silgen_name("_AXUIElementGetWindow")
private func axGetWindow(
  _ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

// MARK: - Accessibility

enum Accessibility {
  static func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success
    else { return nil }
    return result
  }

  static func origin(of element: AXUIElement) -> CGPoint? {
    var point = CGPoint.zero
    guard let raw = axValue(kAXPositionAttribute, of: element),
      AXValueGetValue(raw, .cgPoint, &point)
    else { return nil }
    return point
  }

  static func size(of element: AXUIElement) -> CGSize? {
    var size = CGSize.zero
    guard let raw = axValue(kAXSizeAttribute, of: element), AXValueGetValue(raw, .cgSize, &size)
    else { return nil }
    return size
  }

  @discardableResult
  static func setSize(_ size: CGSize, of element: AXUIElement) -> AXError {
    var value = size
    guard let raw = AXValueCreate(.cgSize, &value) else { return .failure }
    return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, raw)
  }

  @discardableResult
  static func setOrigin(_ origin: CGPoint, of element: AXUIElement) -> AXError {
    var point = origin
    guard let raw = AXValueCreate(.cgPoint, &point) else { return .failure }
    return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, raw)
  }

  /// Every window of every regular app, by window id.
  static func windows() -> [CGWindowID: AXUIElement] {
    var found: [CGWindowID: AXUIElement] = [:]
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
      let element = AXUIElementCreateApplication(app.processIdentifier)
      AXUIElementSetMessagingTimeout(element, 1)
      for window in value(kAXWindowsAttribute, of: element) as? [AXUIElement] ?? [] {
        var windowID = CGWindowID(0)
        if axGetWindow(window, &windowID) == .success, windowID != 0 { found[windowID] = window }
      }
    }
    return found
  }

  private static func axValue(_ attribute: String, of element: AXUIElement) -> AXValue? {
    guard let raw = value(attribute, of: element), CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    return unsafeDowncast(raw, to: AXValue.self)
  }
}

// MARK: - Geometry

/// Where the WindowServer really has a window, which can lag behind what AX reports.
func serverOrigin(of windowID: CGWindowID) -> CGPoint? {
  let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]]
  guard let bounds = list?.first?[kCGWindowBounds as String] as? [String: CGFloat],
    let originX = bounds["X"], let originY = bounds["Y"]
  else { return nil }
  return CGPoint(x: originX, y: originY)
}

// MARK: - Commands

/// `positions <window-id> [x y] [--display <n>]`: asks macOS to put the window at the edges of a
/// display (the primary unless given, or at one given position) and reports where it really went.
func positions(_ given: [String]) throws(UsageError) {
  var arguments = given
  var number = 1
  if let flag = arguments.firstIndex(of: "--display") {
    guard flag + 1 < arguments.count, let parsed = Int(arguments[flag + 1]) else {
      throw UsageError("--display needs a display number (see `displays`)")
    }
    number = parsed
    arguments.removeSubrange(flag...(flag + 1))
  }
  guard let first = arguments.first, let windowID = CGWindowID(first) else {
    throw UsageError("positions <window-id> [x y] [--display <n>]")
  }
  guard let display = Display(number: number) else {
    throw UsageError("no display \(number) (see `displays`)")
  }
  guard let window = Accessibility.windows()[windowID], let home = Accessibility.origin(of: window),
    let size = Accessibility.size(of: window)
  else { throw UsageError("no window \(windowID) (see `tyler window list`)") }

  print("window \(windowID), size \(Int(size.width))x\(Int(size.height)), at \(format(home))")
  print(
    "display \(display.number): \(format(display.frame)), visible frame \(format(display.visible))")
  var requests = edgeRequests(home: home, size: size, display: display)
  if arguments.count == 3, let requested = point(x: arguments[1], y: arguments[2]) {
    requests = [("requested", requested)]
  }
  for (label, request) in requests {
    Accessibility.setOrigin(request, of: window)
    usleep(120_000)  // let the WindowServer catch up
    let actual = Accessibility.origin(of: window) ?? .zero
    let verdict = abs(actual.x - request.x) < 1 && abs(actual.y - request.y) < 1
    let server = serverOrigin(of: windowID).map(format) ?? "?"
    let padded = label.padding(toLength: 26, withPad: " ", startingAt: 0)
    print(
      "\(padded) asked \(format(request)) -> got \(format(actual)) (server \(server))  "
        + (verdict ? "ok" : "CLAMPED"))
  }
  Accessibility.setOrigin(home, of: window)
  print("put back at \(format(home))")
}

private func edgeRequests(
  home: CGPoint, size: CGSize, display: Display
) -> [(String, CGPoint)] {
  let visible = display.visible
  // Measure from inside the display: the window may start on another one.
  let base =
    visible.contains(home) ? home : CGPoint(x: visible.minX + 40, y: visible.minY + 40)
  return [
    ("top: just below menu bar", CGPoint(x: base.x, y: visible.minY)),
    ("top: 1 point higher", CGPoint(x: base.x, y: visible.minY - 1)),
    ("top: off screen", CGPoint(x: base.x, y: display.frame.minY - size.height - 100)),
    ("bottom: 40 points showing", CGPoint(x: base.x, y: display.frame.maxY - 40)),
    ("bottom: 1 point showing", CGPoint(x: base.x, y: display.frame.maxY - 1)),
    ("right: 1 point showing", CGPoint(x: visible.maxX - 1, y: base.y)),
    ("right: none showing", CGPoint(x: visible.maxX, y: base.y)),
    ("left: 1 point showing", CGPoint(x: visible.minX - size.width + 1, y: base.y)),
    ("left: none showing", CGPoint(x: visible.minX - size.width, y: base.y)),
  ]
}

/// `stacking`: the on-screen windows from front to back, with tyler's workspace for each.
func stacking() {
  let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
  let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
  let tyler = TylerWindows.load()
  print("front to back (normal windows only):")
  for entry in list where entry[kCGWindowLayer as String] as? Int == 0 {
    guard let number = entry[kCGWindowNumber as String] as? Int else { continue }
    let owner = entry[kCGWindowOwnerName as String] as? String ?? "?"
    let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let frame = CGRect(
      x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0,
      height: bounds["Height"] ?? 0)
    let info = tyler[number]
    let workspace = info?.workspace.map { "workspace \($0)" } ?? "no workspace"
    print("  \(number)  \(owner)  \(format(frame))  \(workspace)  \(info?.title ?? "")")
  }
}

/// What `tyler window list --json` says about each window, by id; empty if tylerd isn't running.
enum TylerWindows {
  struct Info {
    let workspace: Int?
    let title: String
  }

  static func load() -> [Int: Info] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tylerPath())
    process.arguments = ["window", "list", "--json"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      print("(cannot run tyler: \(error.localizedDescription))")
      return [:]
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let windows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    var result: [Int: Info] = [:]
    for window in windows {
      guard let windowID = window["id"] as? Int else { continue }
      result[windowID] = Info(
        workspace: window["workspace"] as? Int, title: window["title"] as? String ?? "")
    }
    return result
  }

  /// The `tyler` built next to this tool (both live in .build).
  private static func tylerPath() -> String {
    let tool = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    return tool.deletingLastPathComponent().appendingPathComponent("debug/tyler").path
  }
}

/// `menubar`: what tylerd's menu bar item shows, read through Accessibility.
func menubar() throws(UsageError) {
  let tylerd = NSWorkspace.shared.runningApplications.first {
    $0.executableURL?.lastPathComponent == "tylerd"
  }
  guard let tylerd else { throw UsageError("tylerd is not running") }
  let element = AXUIElementCreateApplication(tylerd.processIdentifier)
  guard let raw = Accessibility.value("AXExtrasMenuBar", of: element),
    CFGetTypeID(raw) == AXUIElementGetTypeID()
  else {
    print("tylerd (pid \(tylerd.processIdentifier)) has no menu bar item")
    return
  }
  let bar = unsafeDowncast(raw, to: AXUIElement.self)
  for item in Accessibility.value(kAXChildrenAttribute, of: bar) as? [AXUIElement] ?? [] {
    let title = Accessibility.value(kAXTitleAttribute, of: item) as? String ?? "?"
    let origin = Accessibility.origin(of: item).map(format) ?? "?"
    let size = Accessibility.size(of: item).map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"
    print("title \"\(title)\" at \(origin), \(size)")
  }
  print("(only the text: colours, such as the faint dots, need a look at the screen)")
}

// MARK: - Output and arguments

struct UsageError: Error {
  let message: String
  init(_ message: String) { self.message = message }
}

func modifierFlags(_ name: String) -> CGEventFlags? {
  var flags: CGEventFlags = []
  for part in name.split(separator: "+") {
    switch part {
    case "option": flags.insert(.maskAlternate)
    case "ctrl": flags.insert(.maskControl)
    case "cmd": flags.insert(.maskCommand)
    case "shift": flags.insert(.maskShift)
    default: return nil
    }
  }
  return flags.isEmpty ? nil : flags
}

func point(x horizontal: String, y vertical: String) -> CGPoint? {
  guard let pointX = Double(horizontal), let pointY = Double(vertical) else { return nil }
  return CGPoint(x: pointX, y: pointY)
}

func format(_ point: CGPoint) -> String { "\(Int(point.x)),\(Int(point.y))" }

func format(_ rect: CGRect) -> String {
  "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))"
}

let usage = """
  usage: devtools/live-check <command>
    stacking                      on-screen windows front to back, with tyler's workspace
    menubar                       what tylerd's menu bar item shows
    displays                      every display as tyler numbers it, with its parking edge
    positions <window-id> [x y] [--display <n>]
                                  where macOS really puts a window at a display's edges
    resize <window-id> <x> <y> <width> <height> [--order size-first|move-first]
                                  what each write of a frame really does, then put it back
    slide <seconds> <rounds> <out-ids> <in-id@x,y>... [--display <n>] [--park left|right]
                                  replay a workspace slide on real windows, then restore them
    gestures <seconds>            log trackpad touches from an event tap and a global monitor
    display-events <seconds> [settle]
                                  log display changes, and the displays and windows after each
    pointer <seconds> [rest-ms]   the window under the pointer and any open menus at each rest
    mod-drag <seconds> [modifier] [stall-ms]
                                  hold modifier presses in an active tap: drags are swallowed,
                                  clicks posted again (the mod-drag spike)
    key <combination>...          press keys as if typed, such as option+shift+j (the demo video)
  """

let arguments = Array(CommandLine.arguments.dropFirst())
do {
  switch arguments.first {
  case "stacking": stacking()
  case "menubar": try menubar()
  case "displays": displays()
  case "positions": try positions(Array(arguments.dropFirst()))
  case "resize": try resize(Array(arguments.dropFirst()))
  case "slide": try slide(Array(arguments.dropFirst()))
  case "gestures": try gestures(Array(arguments.dropFirst()))
  case "display-events": try displayEvents(Array(arguments.dropFirst()))
  case "pointer": try pointer(Array(arguments.dropFirst()))
  case "mod-drag": try modDrag(Array(arguments.dropFirst()))
  case "key": try key(Array(arguments.dropFirst()))
  default:
    print(usage)
    exit(arguments.isEmpty ? 0 : 2)
  }
} catch {
  FileHandle.standardError.write(Data("live-check: \(error.message)\n".utf8))
  exit(2)
}

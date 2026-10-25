import AppKit
import Foundation
import TylerConfig
import TylerCore
import TylerIndicators
import TylerPlatform
import TylerProtocol
import TylerRuntime
import TylerServer

/// tylerd's own lines, in the log's format but written whatever `log.level` says: which config,
/// socket and state it uses, and why it can't go on.
func announce(_ message: String) {
  say(message, level: .info, to: .standardOutput)
}

func warn(_ message: String) {
  say(message, level: .error, to: .standardError)
}

func say(_ message: String, level: LogLevel, to handle: FileHandle) {
  let line = LogOutput.line(message, level: level, category: "tylerd", at: Date())
  handle.write(Data((line + "\n").utf8))
}

func die(_ message: String) -> Never {
  warn(message)
  exit(1)
}

let socketPath = Paths.socketPath()
// Before the log, the state and the menu bar: a second tylerd (Tyler.app opened from Spotlight
// while another one runs) would empty the running one's log, and show its own items.
if IPCServer.isServed(path: socketPath) {
  die("socket taken - \(socketPath) - tylerd is already running")
}

// Log lines at or above `log.level` go to stderr: `tyler start` sends it to ~/.tyler/tyler.log,
// and launched by LaunchServices, tylerd opens that file itself.
do {
  let logPath = Paths.logPath()
  if try LogFile.takeDiscardedOutput(to: logPath) { announce("log opened - \(logPath)") }
} catch {
  warn("log opening failed - \(error)")
}
LogOutput.shared.setSink { line in FileHandle.standardError.write(Data((line + "\n").utf8)) }

let statePath = Paths.statePath(socketPath: socketPath)
let configSource = ConfigSource.file(at: Paths.configPath())
let configLoad = configSource.load()
switch configLoad {
case .loaded: announce("config loaded - \(configSource.path)")
case .missing: announce("config missing - \(configSource.path) - using the defaults")
case .broken(let error): warn("config broken - \(configSource.path) - \(error); using the defaults")
}

// AX observers, NSWorkspace notifications and the menu bar item all go through the main run
// loop, so the process runs a real (windowless) AppKit application instead of `dispatchMain()`.
// The application exists before the menu bar item is created.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// A tylerd that restarted left its workspaces here, with the windows where it left them; carry on
// from them instead of tiling everything onto the first workspace.
var handedOver: SavedState?
do {
  handedOver = try SavedState.read(from: statePath)
  if handedOver != nil { announce("state handed over - \(statePath)") }
} catch {
  warn("state reading failed - \(error); starting afresh")
  // A stale file would only be refused again; a file of another version may suit another build.
  if case .stale = error { forgetHandedOverState() }
}

let screenLock = MacScreenLock()
let gate = MacAccessibilityGate(screenLock: screenLock)
// The menu bar items send requests through the router, which only exists once the items do;
// `indicatorRouter` closes that loop.
var indicatorRouter: CommandRouter?
let performFromIndicator: @MainActor (MenuChoice) -> Void = { choice in
  switch choice {
  case .request(let request):
    guard let response = indicatorRouter?.respond(to: request) else {
      warn("menu command dropped - \(request) - tylerd isn't ready yet")
      return
    }
    if case .error(let message) = response { warn("menu command failed - \(message)") }
  case .quit:
    announce("tylerd quitting - chosen in the menu")
    shutDown(handingOver: false)
  }
}
// Items created later sit further left, so the map goes left of the text.
let indicator = IndicatorGroup([
  TextIndicator(perform: performFromIndicator), MapIndicator(perform: performFromIndicator),
])
let manager = WindowManager(
  windowSystem: MacWindowSystem(screenLock: screenLock),
  displays: MacDisplayProvider(),
  gate: gate,
  screenLock: screenLock,
  config: configLoad.config,
  configSource: configSource,
  indicator: indicator,
  pointer: MacPointerInput(),
  stacking: MacWindowStacking(),
  gapCursor: MacGapCursor(),
  restoring: handedOver
)
// The binary's modification time at launch lets `tyler status` notice a rebuild since.
let executablePath =
  Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
var executableModified: Date?
do {
  executableModified =
    try FileManager.default.attributesOfItem(atPath: executablePath)[.modificationDate] as? Date
} catch {
  warn("binary reading failed - \(executablePath) - \(error.localizedDescription)")
}
let status = ServerStatus(
  pid: getpid(),
  executablePath: executablePath,
  executableModified: executableModified,
  startedAt: Date(),
  configPath: configSource.path,
  keepsWindowsOnRestart: true,
  putsWindowsBackOnHandOver: true,
  version: TylerVersion.current,
  // System Settings lists the app by its file name, not its `CFBundleName` (measured).
  appName: Bundle.main.bundleIdentifier == nil ? nil : Bundle.main.bundleURL.lastPathComponent,
  appBundleID: Bundle.main.bundleIdentifier,
  appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
)
let router = CommandRouter(manager: manager, status: status) { openConfigFile() }
indicatorRouter = router
let server = IPCServer(path: socketPath) { [router] request in await router.handle(request) }

do {
  try server.start()
} catch IPCServer.Failure.alreadyRunning(let path) {
  die("socket taken - \(path) - tylerd is already running")
} catch {
  die("socket opening failed - \(error)")
}
announce("socket listening - \(socketPath)")

/// The menu's Open config and `tyler config edit` outside a terminal.
@MainActor
func openConfigFile() -> Response {
  do {
    try TextEditor.open(configSource.path, command: manager.config.editor.command)
    return .message("opened \(configSource.path)")
  } catch {
    warn("config opening failed - \(configSource.path) - \(error.localizedDescription)")
    return .error("cannot open \(configSource.path): \(error.localizedDescription)")
  }
}

/// Once windows are tracked, the handed-over state has been used (or the windows it named are
/// gone), so the file is removed: a later start must not apply it again.
func forgetHandedOverState() {
  guard FileManager.default.fileExists(atPath: statePath) else { return }
  do {
    try FileManager.default.removeItem(atPath: statePath)
  } catch {
    warn("state removing failed - \(statePath) - \(error.localizedDescription)")
  }
}

// Without permission the server still answers; `list` explains what to do. The manager starts
// by itself once permission is granted, and lets go of everything if it is taken away.
if manager.startIfPermitted() {
  announce("windows tracking started")
  forgetHandedOverState()
} else {
  switch manager.access {
  case .screenLocked:
    announce("screen locked - windows tracking starts once it is unlocked")
  case .refused:
    warn(
      "permission refused - Accessibility calls fail although the permission is on; its entry "
        + "in System Settings > Privacy & Security may be stale (see docs/troubleshooting.md)")
  case .notTrusted, .ok, .checking, .blind:
    gate.prompt()
    announce("permission waiting - Accessibility, in System Settings > Privacy & Security")
  }
}
let permissionPoll = Task { @MainActor in
  await manager.followPermission {
    announce("windows tracking started - Accessibility works now")
    forgetHandedOverState()
  }
}

/// Writes the workspaces down for the next tylerd (`tyler restart`), leaving every window where it
/// is, or first putting it back where it was. If the file can't be written, the next tylerd tiles
/// the windows afresh.
@MainActor
func handOver(puttingWindowsBack: Bool) {
  guard var saved = manager.handOver(puttingWindowsBack: puttingWindowsBack) else { return }
  saved.writtenAt = Date()
  do {
    try saved.write(to: statePath)
  } catch {
    warn("state saving failed - \(error); the next tylerd will tile the windows afresh")
  }
}

/// Shuts down cleanly: `manager.stop()` puts every window (parked ones included) back where it
/// was before tylerd moved it, and the socket file doesn't linger. Handing over (`tyler restart`)
/// leaves the windows in place instead, or puts them back and still hands the workspaces over.
@MainActor
func shutDown(handingOver: Bool, puttingWindowsBack: Bool = false) {
  permissionPoll.cancel()
  if handingOver { handOver(puttingWindowsBack: puttingWindowsBack) } else { manager.stop() }
  server.stop()
  exit(0)
}

// SIGINT/SIGTERM stop; `tyler restart` sends SIGUSR1 to hand over, or SIGUSR2 to hand over with
// the windows put back. A crash or `kill -9` skips all of them and leaves parked windows at the
// edge.
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGINT, SIGTERM, SIGUSR1, SIGUSR2] {
  signal(signalNumber, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
  source.setEventHandler {
    MainActor.assumeIsolated {
      shutDown(
        handingOver: signalNumber == SIGUSR1 || signalNumber == SIGUSR2,
        puttingWindowsBack: signalNumber == SIGUSR2)
    }
  }
  source.resume()
  signalSources.append(source)
}

application.run()

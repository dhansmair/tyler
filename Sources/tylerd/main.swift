import AppKit
import Foundation
import TylerCore
import TylerIndicators
import TylerPlatform
import TylerServer

func announce(_ message: String) {
  FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

func warn(_ message: String) {
  FileHandle.standardError.write(Data(("tylerd: " + message + "\n").utf8))
}

func die(_ message: String) -> Never {
  warn(message)
  exit(1)
}

let socketPath = Paths.socketPath()
let statePath = Paths.statePath(socketPath: socketPath)
let configSource = ConfigSource.file(at: Paths.configPath())
let configLoad = configSource.load()
switch configLoad {
case .loaded: announce("tylerd: config \(configSource.path)")
case .missing: announce("tylerd: no config file at \(configSource.path), using the defaults")
case .broken(let error): warn("\(configSource.path): \(error) (using the defaults)")
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
  if handedOver != nil { announce("tylerd: carrying on from \(statePath)") }
} catch {
  warn("\(error) (starting afresh)")
}

let gate = SystemAccessibilityGate()
// The menu bar items send requests to the manager, which only exists once the items do;
// `indicatorTarget` closes that loop.
var indicatorTarget: WindowManager?
let performFromIndicator: @MainActor (Request) -> Void = { request in
  guard let response = indicatorTarget?.handle(request) else { return }
  if case .error(let message) = response { warn(message) }
}
// Items created later sit further left, so the map goes left of the text.
let indicator = IndicatorGroup([
  TextIndicator(perform: performFromIndicator), MapIndicator(perform: performFromIndicator),
])
let manager = WindowManager(
  backend: AXBackend(),
  displays: ScreenDisplayProvider(),
  gate: gate,
  config: configLoad.config,
  configSource: configSource,
  indicator: indicator,
  pointer: SystemPointerInput(),
  restoring: handedOver
)
indicatorTarget = manager
// The binary's modification time at launch lets `tyler status` notice a rebuild since.
let executablePath =
  Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
var executableModified: Date?
do {
  executableModified =
    try FileManager.default.attributesOfItem(atPath: executablePath)[.modificationDate] as? Date
} catch {
  warn("cannot read the modification time of \(executablePath): \(error.localizedDescription)")
}
let status = ServerStatus(
  pid: getpid(),
  executablePath: executablePath,
  executableModified: executableModified,
  startedAt: Date(),
  configPath: configSource.path,
  keepsWindowsOnRestart: true
)
let router = CommandRouter(manager: manager, status: status)
let server = IPCServer(path: socketPath) { [router] request in await router.handle(request) }

do {
  try server.start()
} catch IPCServer.Failure.alreadyRunning(let path) {
  die("already running (socket \(path))")
} catch {
  die("cannot start: \(error)")
}
announce("tylerd: listening on \(socketPath)")

/// Once windows are tracked, the handed-over state has been used (or the windows it named are
/// gone), so the file is removed: a later start must not apply it again.
func forgetHandedOverState() {
  guard FileManager.default.fileExists(atPath: statePath) else { return }
  do {
    try FileManager.default.removeItem(atPath: statePath)
  } catch {
    warn("cannot remove \(statePath): \(error.localizedDescription)")
  }
}

// Without permission the server still answers; `list` explains what to do. The manager starts
// by itself once permission is granted.
var permissionPoll: Task<Void, Never>?
if manager.startIfPermitted() {
  announce("tylerd: tracking windows")
  forgetHandedOverState()
} else {
  gate.prompt()
  announce("tylerd: waiting for Accessibility permission (System Settings > Privacy & Security)")
  permissionPoll = Task { @MainActor in
    guard await manager.startWhenPermitted() else { return }  // Cancelled during shutdown.
    announce("tylerd: Accessibility permission granted, tracking windows")
    forgetHandedOverState()
  }
}

/// Leaves every window where it is and writes the workspaces down for the next tylerd (`tyler
/// restart`). If the file can't be written, the next tylerd tiles the windows afresh.
@MainActor
func handOver() {
  guard let saved = manager.handOver() else { return }
  do {
    try saved.write(to: statePath)
  } catch {
    warn("\(error); the next tylerd will tile the windows afresh")
  }
}

// Shut down cleanly on SIGINT/SIGTERM: `manager.stop()` puts every window (parked ones included)
// back where it was before tylerd moved it, and the socket file doesn't linger. SIGUSR1 (sent by
// `tyler restart`) hands over instead and leaves the windows in place. A crash or `kill -9` skips
// both and leaves parked windows at the right edge.
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGINT, SIGTERM, SIGUSR1] {
  signal(signalNumber, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
  source.setEventHandler {
    MainActor.assumeIsolated {
      permissionPoll?.cancel()
      if signalNumber == SIGUSR1 { handOver() } else { manager.stop() }
    }
    server.stop()
    exit(0)
  }
  source.resume()
  signalSources.append(source)
}

application.run()

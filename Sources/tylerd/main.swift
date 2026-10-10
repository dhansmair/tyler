import AppKit
import Foundation
import TylerCore
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
let configSource = ConfigSource.file(at: Paths.configPath())
// A broken config doesn't stop tylerd: it starts with the defaults, and `tyler reload` picks
// up the file once it is fixed.
var config = Config()
do {
  if let loaded = try configSource.read() {
    config = loaded
    announce("tylerd: config \(configSource.path)")
  } else {
    announce("tylerd: no config file at \(configSource.path), using the defaults")
  }
} catch {
  warn("\(configSource.path): \(error) (using the defaults)")
}

// AX observers, NSWorkspace notifications and the menu bar item all go through the main run
// loop, so the process runs a real (windowless) AppKit application instead of `dispatchMain()`.
// The application exists before the menu bar item is created.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let gate = SystemAccessibilityGate()
// The menu bar item's menu sends requests to the manager, which only exists once the item
// does; `indicatorTarget` closes that loop.
var indicatorTarget: WindowManager?
let indicator = StatusBarIndicator { request in
  guard let response = indicatorTarget?.handle(request) else { return }
  if case .error(let message) = response { warn(message) }
}
let manager = WindowManager(
  backend: AXBackend(),
  displays: ScreenDisplayProvider(),
  gate: gate,
  config: config,
  configSource: configSource,
  indicator: indicator
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
  configPath: configSource.path
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

// Without permission the server still answers; `list` explains what to do. Poll until it is
// granted so the user doesn't have to restart tylerd.
var permissionPoll: Task<Void, Never>?
if manager.startIfPermitted() {
  announce("tylerd: tracking windows")
} else {
  gate.prompt()
  announce("tylerd: waiting for Accessibility permission (System Settings > Privacy & Security)")
  permissionPoll = Task { @MainActor in
    while !manager.startIfPermitted() {
      do {
        try await Task.sleep(for: .seconds(1))
      } catch {
        return  // Cancelled during shutdown.
      }
    }
    announce("tylerd: Accessibility permission granted, tracking windows")
  }
}

// Shut down cleanly on SIGINT/SIGTERM: `manager.stop()` puts every window (parked ones included)
// back where it was before tylerd moved it, and the socket file doesn't linger. A crash or
// `kill -9` skips this and leaves parked windows in the corner.
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGINT, SIGTERM] {
  signal(signalNumber, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
  source.setEventHandler {
    MainActor.assumeIsolated {
      permissionPoll?.cancel()
      manager.stop()
    }
    server.stop()
    exit(0)
  }
  source.resume()
  signalSources.append(source)
}

application.run()

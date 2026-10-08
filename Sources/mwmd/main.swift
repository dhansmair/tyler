import AppKit
import Foundation
import MWMCore
import MWMPlatform
import MWMServer

func announce(_ message: String) {
  FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

func die(_ message: String) -> Never {
  FileHandle.standardError.write(Data(("mwmd: " + message + "\n").utf8))
  exit(1)
}

let socketPath = Paths.socketPath()
let gate = SystemAccessibilityGate()
let manager = WindowManager(
  backend: AXBackend(),
  displays: ScreenDisplayProvider(),
  gate: gate
)
let router = CommandRouter(manager: manager)
let server = IPCServer(path: socketPath) { [router] request in await router.handle(request) }

do {
  try server.start()
} catch IPCServer.Failure.alreadyRunning(let path) {
  die("already running (socket \(path))")
} catch {
  die("cannot start: \(error)")
}
announce("mwmd: listening on \(socketPath)")

// AX observers and NSWorkspace notifications are delivered through the main run loop, so the
// process runs a real (windowless) AppKit application instead of `dispatchMain()`.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// Without permission the server still answers; `list` explains what to do. Poll until it is
// granted so the user doesn't have to restart mwmd.
var permissionPoll: Task<Void, Never>?
if manager.startIfPermitted() {
  announce("mwmd: tracking windows")
} else {
  gate.prompt()
  announce("mwmd: waiting for Accessibility permission (System Settings > Privacy & Security)")
  permissionPoll = Task { @MainActor in
    while !manager.startIfPermitted() {
      do {
        try await Task.sleep(for: .seconds(1))
      } catch {
        return  // Cancelled during shutdown.
      }
    }
    announce("mwmd: Accessibility permission granted, tracking windows")
  }
}

// Shut down cleanly on SIGINT/SIGTERM so the socket file doesn't linger.
// From M4 on, this is also where parked windows get restored.
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

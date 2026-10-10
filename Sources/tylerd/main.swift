import AppKit
import Foundation
import TylerCore
import TylerPlatform
import TylerServer

func announce(_ message: String) {
  FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

func die(_ message: String) -> Never {
  FileHandle.standardError.write(Data(("tylerd: " + message + "\n").utf8))
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
announce("tylerd: listening on \(socketPath)")

// AX observers and NSWorkspace notifications are delivered through the main run loop, so the
// process runs a real (windowless) AppKit application instead of `dispatchMain()`.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

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

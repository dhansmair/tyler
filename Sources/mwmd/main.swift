import Dispatch
import Foundation
import MWMCore
import MWMServer

let path = Paths.socketPath()
let router = CommandRouter()
let server = IPCServer(path: path) { router.handle($0) }

do {
  try server.start()
} catch IPCServer.Failure.alreadyRunning(let path) {
  FileHandle.standardError.write(Data("mwmd: already running (socket \(path))\n".utf8))
  exit(1)
} catch {
  FileHandle.standardError.write(Data("mwmd: cannot start: \(error)\n".utf8))
  exit(1)
}

FileHandle.standardOutput.write(Data("mwmd: listening on \(path)\n".utf8))

// Shut down cleanly on SIGINT/SIGTERM so the socket file doesn't linger.
// From M4 on, this is also where parked windows get restored.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
  signal(sig, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
  source.setEventHandler {
    server.stop()
    exit(0)
  }
  source.resume()
  signalSources.append(source)
}

dispatchMain()

import CoreGraphics
import Foundation
import TylerClient
import TylerProtocol
import TylerRuntime

func fail(_ message: String, code: Int32) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(code)
}

let invocation: Invocation
do {
  invocation = try CommandLineParser.parse(Array(CommandLine.arguments.dropFirst()))
} catch CommandLineError.usage(let message) {
  fail("tyler: \(message)\n\n\(CommandLineParser.usage)", code: 2)
} catch {
  fail("tyler: \(error)", code: 2)
}

func show(_ response: Response) {
  let (text, success) = ResponseFormatter.format(response, as: invocation.format)
  if success {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
  } else {
    fail("tyler: \(text)", code: 1)
  }
}

switch invocation.action {
case .send(var request):
  // `debug at` without a point asks about the pointer, which only this side can read.
  if case .debugAt(nil) = request { request = .debugAt(CGEvent(source: nil)?.location) }
  do {
    show(try IPCClient().send(request))
  } catch IPCClientError.serverNotRunning(let path) {
    fail(
      "tyler: tylerd is not running (no server at \(path)); start it with `tyler start`", code: 1)
  } catch {
    fail("tyler: \(error)", code: 1)
  }
case .printVersion:
  FileHandle.standardOutput.write(Data("tyler \(TylerVersion.current)\n".utf8))
case .daemon(let command):
  guard let client = Bundle.main.executableURL else {
    fail("tyler: cannot find its own executable, so it doesn't know where tylerd is", code: 1)
  }
  let controller = DaemonController(
    system: ProcessDaemonSystem(),
    serverPath: DaemonController.serverPath(nextTo: client),
    logPath: Paths.logPath())
  show(controller.run(command))
}

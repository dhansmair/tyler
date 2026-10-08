import Foundation
import MWMClient
import MWMCore

func fail(_ message: String, code: Int32) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(code)
}

let invocation: Invocation
do {
  invocation = try CommandLineParser.parse(Array(CommandLine.arguments.dropFirst()))
} catch CommandLineError.usage(let message) {
  fail("mwm: \(message)\n\n\(CommandLineParser.usage)", code: 2)
} catch {
  fail("mwm: \(error)", code: 2)
}

do {
  let response = try IPCClient().send(invocation.request)
  let (text, success) = ResponseFormatter.format(response, as: invocation.format)
  if success {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
  } else {
    fail("mwm: \(text)", code: 1)
  }
} catch IPCClientError.serverNotRunning(let path) {
  fail("mwm: mwmd is not running (no server at \(path))", code: 1)
} catch {
  fail("mwm: \(error)", code: 1)
}

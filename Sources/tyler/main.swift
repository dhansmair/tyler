import Foundation
import TylerClient
import TylerCore

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

do {
  let response = try IPCClient().send(invocation.request)
  let (text, success) = ResponseFormatter.format(response, as: invocation.format)
  if success {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
  } else {
    fail("tyler: \(text)", code: 1)
  }
} catch IPCClientError.serverNotRunning(let path) {
  fail("tyler: tylerd is not running (no server at \(path))", code: 1)
} catch {
  fail("tyler: \(error)", code: 1)
}

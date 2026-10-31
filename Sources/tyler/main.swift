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

func answer(to request: Request) -> Response {
  do {
    return try IPCClient().send(request)
  } catch IPCClientError.serverNotRunning(let path) {
    fail(
      "tyler: tylerd is not running (no server at \(path)); start it with `tyler start`", code: 1)
  } catch {
    fail("tyler: \(error)", code: 1)
  }
}

func send(_ request: Request) {
  show(answer(to: request))
}

/// On stderr, so that a pipe gets only the log.
func setLogLevel(_ level: LogLevel) {
  let request = Request.configSet(name: "log.level", value: level.rawValue)
  let (text, success) = ResponseFormatter.format(answer(to: request), as: .text)
  guard success else { fail("tyler: \(text)", code: 1) }
  let note = "tyler: log.level is \(level.rawValue) until `tyler config reload` or tylerd stops\n"
  FileHandle.standardError.write(Data(note.utf8))
}

/// Edits tylerd's config file here and reloads it; without tylerd, the file it would read.
func editInTerminal(with editor: String) {
  var status: ServerStatus?
  do {
    if case .status(let answer) = try IPCClient().send(.status) { status = answer }
  } catch IPCClientError.serverNotRunning {
    // Nothing to reload then, and the file is still worth editing.
  } catch {
    fail("tyler: \(error)", code: 1)
  }
  do {
    try TerminalEditor.edit(status?.configPath ?? Paths.configPath(), with: editor)
  } catch {
    fail("tyler: \(error)", code: 1)
  }
  if status != nil { send(.reload) }
}

switch invocation.action {
case .send(var request):
  // `debug at` without a point asks about the pointer, which only this side can read.
  if case .debugAt(nil) = request { request = .debugAt(CGEvent(source: nil)?.location) }
  send(request)
case .editConfig:
  let isTerminal = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
  let environment = ProcessInfo.processInfo.environment
  switch ConfigEditing.choose(isTerminal: isTerminal, environment: environment) {
  case .inTerminal(let editor): editInTerminal(with: editor)
  case .byServer: send(.configEdit)
  }
case .showLog(let level):
  if let level { setLogLevel(level) }
  do {
    try LogViewer.show(Paths.logPath(), isTerminal: isatty(STDOUT_FILENO) == 1)
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
    logPath: Paths.logPath(),
    app: AppLaunch.nextTo(
      client, home: NSHomeDirectory(), socketPath: Paths.socketPath(),
      environment: ProcessInfo.processInfo.environment,
      workingDirectory: FileManager.default.currentDirectoryPath))
  show(controller.run(command))
}

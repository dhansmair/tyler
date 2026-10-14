import Foundation
import Testing
import TylerCore

@testable import TylerConfig

@Suite("Config")
struct ConfigTests {
  @Test(arguments: ["", "# nothing set yet\n", "[gaps]"])
  func missingSettingsUseTheDefaults(text: String) throws {
    #expect(try Config.parse(text) == Config())
    #expect(Config().gaps == Config.Gaps(inner: 0, outer: 0))
    #expect(
      Config().mouse
        == Config.Mouse(followInterval: 16, focusFollows: false, focusDelay: 100, modifier: .option)
    )
  }

  @Test(arguments: [0, 33, 1000])
  func parsesTheMouseFollowInterval(milliseconds: Int) throws {
    let config = try Config.parse("[mouse]\nfollow-interval = \(milliseconds)")
    #expect(config.mouse == Config.Mouse(followInterval: milliseconds))
    #expect(config.gaps == Config.Gaps(), "the other settings keep their defaults")
  }

  @Test(arguments: [0, 250, 1000])
  func parsesFocusFollowsMouse(milliseconds: Int) throws {
    let config = try Config.parse("[mouse]\nfocus-follows = true\nfocus-delay = \(milliseconds)")
    #expect(config.mouse == Config.Mouse(focusFollows: true, focusDelay: milliseconds))
  }

  @Test func parsesGapResize() throws {
    #expect(Config().mouse.gapResize)
    #expect(try !Config.parse("[mouse]\ngap-resize = false").mouse.gapResize)
  }

  @Test(arguments: [1, 6, 10])
  func parsesTheWorkspaceCount(count: Int) throws {
    #expect(try Config.parse("[workspaces]\ncount = \(count)").workspaces.count == count)
  }

  @Test(arguments: ["", "open -na Ghostty --args -e nvim"])
  func parsesTheEditorCommand(command: String) throws {
    let config = try Config.parse("[editor]\ncommand = \"\(command)\"")
    #expect(config.editor == Config.Editor(command: command))
    #expect(Config().editor.command.isEmpty)
  }

  @Test func fourWorkspacesByDefault() {
    #expect(Config().workspaces.count == 4)
  }

  @Test func displaysListTheirWorkspaces() throws {
    let config = try Config.parse(
      """
      [displays.1]
      workspaces = [4, 1, 2]

      [displays.3]
      workspaces = [7]
      """)
    #expect(config.displays == [1: [1, 2, 4], 3: [7]])
  }

  @Test func aDisplayWithoutAListGetsTheCount() throws {
    let config = try Config.parse("[displays.2]")
    #expect(config.displays.isEmpty)
    #expect(config.workspaceNumbers(displayCount: 2) == [[1, 2, 3, 4], [5, 6, 7, 8]])
  }

  /// The displays' lists, how many displays are connected, and the numbers each display gets.
  struct NumberingCase: Sendable {
    let displays: [Int: [Int]]
    let displayCount: Int
    let numbers: [[Int]]
  }

  @Test(arguments: [
    NumberingCase(displays: [:], displayCount: 1, numbers: [[1, 2, 3, 4]]),
    NumberingCase(displays: [:], displayCount: 2, numbers: [[1, 2, 3, 4], [5, 6, 7, 8]]),
    NumberingCase(
      displays: [1: [1, 2], 2: [5, 6, 7]], displayCount: 1, numbers: [[1, 2], [5, 6, 7]]),
    NumberingCase(
      displays: [1: [1, 2], 2: [5, 6, 7]], displayCount: 3,
      numbers: [[1, 2], [5, 6, 7], [8, 9, 10, 11]]),
    NumberingCase(displays: [2: [5]], displayCount: 2, numbers: [[6, 7, 8, 9], [5]]),
  ])
  func eachDisplayGetsItsListOrTheNextCountWorkspaces(_ numbering: NumberingCase) {
    let config = Config(displays: numbering.displays)
    #expect(config.workspaceNumbers(displayCount: numbering.displayCount) == numbering.numbers)
  }

  @Test(arguments: [
    ("gap = 8", "unknown setting 'gap'"),
    ("[gaps]\ninnr = 8", "unknown setting 'gaps.innr' (use inner or outer)"),
    ("gaps = 8", "gaps must be a table: write [gaps] and put inner and outer below it"),
    (
      "[editor]\ncommand = 1",
      "editor.command must be a shell command, such as \"open -na Ghostty --args -e nvim\""
    ),
    ("[gaps]\ninner = -1", "gaps.inner must be a whole number of points, 0 or more"),
    ("[gaps]\nouter = 2.5", "gaps.outer must be a whole number of points, 0 or more"),
    ("[gaps]\ninner = \"8\"", "gaps.inner must be a whole number of points, 0 or more"),
    (
      "mouse = 50",
      "mouse must be a table: write [mouse] and put follow-interval, focus-follows, focus-delay,"
        + " modifier and gap-resize below it"
    ),
    (
      "[mouse]\ninterval = 50",
      "unknown setting 'mouse.interval' (use follow-interval, focus-follows, focus-delay, modifier or gap-resize)"
    ),
    ("[mouse]\nfocus-follows = 1", "mouse.focus-follows must be true or false"),
    (
      "[mouse]\nfocus-delay = 1001",
      "mouse.focus-delay must be a whole number of milliseconds, 0 to 1000"
    ),
    (
      "[mouse]\nfocus-delay = -5",
      "mouse.focus-delay must be a whole number of milliseconds, 0 to 1000"
    ),
    (
      "[mouse]\nfollow-interval = -1",
      "mouse.follow-interval must be a whole number of milliseconds, 0 to 1000"
    ),
    (
      "[mouse]\nfollow-interval = 1001",
      "mouse.follow-interval must be a whole number of milliseconds, 0 to 1000"
    ),
    (
      "[mouse]\nfollow-interval = 0.05",
      "mouse.follow-interval must be a whole number of milliseconds, 0 to 1000"
    ),
    (
      "gestures = 3",
      "gestures must be a table: write [gestures] and put swipe, fingers and swipe-distance below it"
    ),
    (
      "[gestures]\nswype = true",
      "unknown setting 'gestures.swype' (use swipe, fingers or swipe-distance)"
    ),
    ("[gestures]\nswipe = 1", "gestures.swipe must be true or false"),
    ("[gestures]\nfingers = 2", "gestures.fingers must be 3 or 4"),
    ("[gestures]\nfingers = 5", "gestures.fingers must be 3 or 4"),
    (
      "[gestures]\nswipe-distance = 0.05",
      "gestures.swipe-distance must be a number of trackpad widths, 0.1 to 1.0"
    ),
    (
      "[gestures]\nswipe-distance = \"0.3\"",
      "gestures.swipe-distance must be a number of trackpad widths, 0.1 to 1.0"
    ),
    ("workspaces = 4", "workspaces must be a table: write [workspaces] and put count below it"),
    ("[workspaces]\nnumber = 4", "unknown setting 'workspaces.number' (use count)"),
    ("[workspaces]\ncount = 0", "workspaces.count must be a whole number, 1 to 10"),
    ("[workspaces]\ncount = 11", "workspaces.count must be a whole number, 1 to 10"),
    ("[workspaces]\ncount = \"4\"", "workspaces.count must be a whole number, 1 to 10"),
    ("displays = 1", "displays must be a table: write [displays.<n>] and put workspaces below it"),
    ("[displays.0]\nworkspaces = [1]", "displays.0: name a display by its number, 1 or more"),
    (
      "[displays.laptop]\nworkspaces = [1]",
      "displays.laptop: name a display by its number, 1 or more"
    ),
    ("[displays.01]\nworkspaces = [1]", "displays.01: name a display by its number, 1 or more"),
    (
      "[displays.1]\nworkspaces = 1",
      "displays.1.workspaces must list workspace numbers, 1 to 99, like [1, 2, 3]"
    ),
    (
      "[displays.1]\nworkspaces = [0]",
      "displays.1.workspaces must list workspace numbers, 1 to 99, like [1, 2, 3]"
    ),
    (
      "[displays.1]\nworkspaces = [100]",
      "displays.1.workspaces must list workspace numbers, 1 to 99, like [1, 2, 3]"
    ),
    (
      "[displays.1]\nworkspaces = [\"1\"]",
      "displays.1.workspaces must list workspace numbers, 1 to 99, like [1, 2, 3]"
    ),
    ("[displays.1]\nworkspaces = []", "displays.1.workspaces must list 1 to 10 workspaces"),
    (
      "[displays.1]\nworkspaces = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]",
      "displays.1.workspaces must list 1 to 10 workspaces"
    ),
    ("[displays.1]\nworkspaces = [1, 1]", "displays.1.workspaces lists workspace 1 twice"),
    (
      "[displays.1]\nworkspaces = [1, 2]\n[displays.2]\nworkspaces = [2, 3]",
      "workspace 2 is listed for display 1 and display 2"
    ),
    (
      "[displays]\n1 = [1, 2]",
      "displays.1 must be a table: write [displays.1] and put workspaces below it"
    ),
    ("[displays.1]\ncount = 2", "unknown setting 'displays.1.count' (use workspaces)"),
  ])
  func rejectsInvalidSettings(text: String, message: String) {
    #expect(throws: ConfigError.invalid(message)) {
      try Config.parse(text)
    }
  }

  @Test func syntaxErrorsKeepTheirLine() {
    let error = ConfigError.syntax(TOMLError(line: 2, message: "expected '=' after the key"))
    #expect(throws: error) {
      try Config.parse("[gaps]\ninner 8")
    }
    #expect(error.description == "line 2: expected '=' after the key")
  }

  // MARK: - Reading the file

  private func temporaryPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("tyler-\(UUID().uuidString).toml").path
  }

  @Test func aMissingFileReadsAsNoConfig() throws {
    #expect(try ConfigSource.file(at: temporaryPath()).read() == nil)
  }

  @Test func readsTheFile() throws {
    let path = temporaryPath()
    try "[gaps]\ninner = 6\n".write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }

    let source = ConfigSource.file(at: path)
    #expect(source.path == path)
    #expect(try source.read() == Config(gaps: Config.Gaps(inner: 6)))
  }

  @Test func aBrokenFileThrows() throws {
    let path = temporaryPath()
    try "gap = 8\n".write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }

    #expect(throws: ConfigError.invalid("unknown setting 'gap'")) {
      try ConfigSource.file(at: path).read()
    }
  }

  @Test func loadingAtStartFallsBackToTheDefaults() {
    let gaps = Config(gaps: Config.Gaps(inner: 6))
    #expect(ConfigSource(path: "x") { gaps }.load() == .loaded(gaps))
    #expect(ConfigSource(path: "x") { nil }.load() == .missing)
    let broken = ConfigSource(path: "x") { () throws(ConfigError) -> Config? in
      throw .invalid("unknown setting 'gap'")
    }
    #expect(broken.load() == .broken(.invalid("unknown setting 'gap'")))
    #expect(broken.load().config == Config())
    #expect(ConfigLoad.missing.config == Config())
  }
}

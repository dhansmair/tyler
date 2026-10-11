import Foundation
import Testing

@testable import TylerCore

@Suite("Config")
struct ConfigTests {
  @Test(arguments: ["", "# nothing set yet\n", "[gaps]"])
  func missingSettingsUseTheDefaults(text: String) throws {
    #expect(try Config.parse(text) == Config())
    #expect(Config().gaps == Config.Gaps(inner: 0, outer: 0))
    #expect(Config().mouse == Config.Mouse(followInterval: 50))
  }

  @Test(arguments: [0, 33, 1000])
  func parsesTheMouseFollowInterval(milliseconds: Int) throws {
    let config = try Config.parse("[mouse]\nfollow-interval = \(milliseconds)")
    #expect(config.mouse == Config.Mouse(followInterval: milliseconds))
    #expect(config.gaps == Config.Gaps(), "the other settings keep their defaults")
  }

  @Test(arguments: [1, 6, 10])
  func parsesTheWorkspaceCount(count: Int) throws {
    #expect(try Config.parse("[workspaces]\ncount = \(count)").workspaces.count == count)
  }

  @Test func fourWorkspacesByDefault() {
    #expect(Config().workspaces.count == 4)
  }

  @Test func parsesAppAssignmentsByNameOrBundleID() throws {
    let config = try Config.parse(
      """
      [workspaces]
      count = 5

      [assign]
      Firefox = 3
      "com.mitchellh.ghostty" = 5
      """)
    #expect(config.assignments == ["firefox": 3, "com.mitchellh.ghostty": 5])
    #expect(config.assignedWorkspace(bundleID: "org.mozilla.firefox", appName: "Firefox") == 3)
    #expect(config.assignedWorkspace(bundleID: "COM.mitchellh.Ghostty", appName: "Ghostty") == 5)
    #expect(config.assignedWorkspace(bundleID: nil, appName: "Safari") == nil)
  }

  @Test func theBundleIDWinsOverTheAppName() {
    let config = Config(assignments: ["firefox": 2, "org.mozilla.firefox": 3])
    #expect(config.assignedWorkspace(bundleID: "org.mozilla.firefox", appName: "Firefox") == 3)
  }

  @Test func parsesGaps() throws {
    let config = try Config.parse(
      """
      [gaps]
      inner = 8
      outer = 12
      """)
    #expect(config.gaps == Config.Gaps(inner: 8, outer: 12))
  }

  @Test func parsesGapsWrittenAsDottedKeys() throws {
    #expect(try Config.parse("gaps.outer = 4").gaps == Config.Gaps(inner: 0, outer: 4))
  }

  @Test func gesturesDefaultToAThreeFingerSwipe() throws {
    #expect(
      try Config.parse("").gestures == Config.Gestures(swipe: true, fingers: 3, swipeDistance: 0.3))
  }

  @Test func parsesGestures() throws {
    let config = try Config.parse(
      """
      [gestures]
      swipe = false
      fingers = 4
      swipe-distance = 0.5
      """)
    #expect(config.gestures == Config.Gestures(swipe: false, fingers: 4, swipeDistance: 0.5))
  }

  @Test func aWholeSwipeDistanceMayBeWrittenWithoutAPoint() throws {
    #expect(try Config.parse("gestures.swipe-distance = 1").gestures.swipeDistance == 1)
  }

  @Test func displaysListTheirWorkspaces() throws {
    let config = try Config.parse(
      """
      [displays]
      1 = [4, 1, 2]
      3 = [7]

      [assign]
      Firefox = 7
      """)
    #expect(config.displays == [1: [1, 2, 4], 3: [7]])
    #expect(config.assignments == ["firefox": 7])
  }

  /// `[displays]`, how many displays are connected, and the numbers each display gets.
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

  @Test func withoutDisplaysAnAssignmentMayNameAnotherDisplaysWorkspace() throws {
    #expect(try Config.parse("[assign]\nFirefox = 7").assignments == ["firefox": 7])
  }

  @Test(arguments: [
    ("gap = 8", "unknown setting 'gap'"),
    ("[gaps]\ninnr = 8", "unknown setting 'gaps.innr' (use inner or outer)"),
    ("gaps = 8", "gaps must be a table: write [gaps] and put inner and outer below it"),
    ("[gaps]\ninner = -1", "gaps.inner must be a whole number of points, 0 or more"),
    ("[gaps]\nouter = 2.5", "gaps.outer must be a whole number of points, 0 or more"),
    ("[gaps]\ninner = \"8\"", "gaps.inner must be a whole number of points, 0 or more"),
    ("mouse = 50", "mouse must be a table: write [mouse] and put follow-interval below it"),
    ("[mouse]\ninterval = 50", "unknown setting 'mouse.interval' (use follow-interval)"),
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
    ("assign = 3", "assign must be a table: write [assign] and put app = workspace below it"),
    ("[assign]\nFirefox = 0", "assign.Firefox must be a workspace number, 1 to 99"),
    ("[assign]\nFirefox = 100", "assign.Firefox must be a workspace number, 1 to 99"),
    ("[assign]\nFirefox = \"3\"", "assign.Firefox must be a workspace number, 1 to 99"),
    (
      "[assign]\nFirefox = 7\n[displays]\n1 = [1, 2]\n2 = [5]",
      "assign.Firefox = 7, but [displays] lists no workspace 7"
    ),
    ("displays = 1", "displays must be a table: write [displays] and put 1 = [1, 2, 3] below it"),
    ("[displays]\n0 = [1]", "displays.0: name a display by its number, 1 or more"),
    ("[displays]\nlaptop = [1]", "displays.laptop: name a display by its number, 1 or more"),
    ("[displays]\n01 = [1]", "displays.01: name a display by its number, 1 or more"),
    ("[displays]\n1 = 1", "displays.1 must list workspace numbers, 1 to 99, like [1, 2, 3]"),
    ("[displays]\n1 = [0]", "displays.1 must list workspace numbers, 1 to 99, like [1, 2, 3]"),
    ("[displays]\n1 = [100]", "displays.1 must list workspace numbers, 1 to 99, like [1, 2, 3]"),
    ("[displays]\n1 = [\"1\"]", "displays.1 must list workspace numbers, 1 to 99, like [1, 2, 3]"),
    ("[displays]\n1 = []", "displays.1 must list 1 to 10 workspaces"),
    (
      "[displays]\n1 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]",
      "displays.1 must list 1 to 10 workspaces"
    ),
    ("[displays]\n1 = [1, 1]", "displays.1 lists workspace 1 twice"),
    ("[displays]\n1 = [1, 2]\n2 = [2, 3]", "workspace 2 is listed for display 1 and display 2"),
    (
      "[assign]\norg.mozilla.firefox = 3",
      "assign.org is a table: quote app names and bundle IDs that contain dots"
    ),
    (
      "[assign]\nFirefox = 3\nfirefox = 2",
      "assign.firefox is set twice (app names and bundle IDs ignore case)"
    ),
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

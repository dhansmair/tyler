import Foundation
import Testing

@testable import TylerClient

@Suite("AppLaunch")
struct AppLaunchTests {
  @Test func theAppIsNextToTyler() {
    let app = AppLaunch.nextTo(
      URL(fileURLWithPath: "/opt/tyler/bin/tyler"), socketPath: "/s.sock", environment: [:],
      workingDirectory: "/work")
    #expect(app.path == "/opt/tyler/bin/Tyler.app")
    #expect(app.executablePath == "/opt/tyler/bin/Tyler.app/Contents/MacOS/tylerd")
  }

  @Test func itIsToldTheSocketAndWhatASpawnedTylerdInherited() {
    let environment = [
      "TYLER_CONFIG": "/c.toml", "PATH": "/bin", "EDITOR": "vi", "VISUAL": "", "HOME": "/home",
      "TYLER_SOCKET": "/ignored.sock",
    ]
    let app = AppLaunch.nextTo(
      URL(fileURLWithPath: "/bin/tyler"), socketPath: "/s.sock", environment: environment,
      workingDirectory: "/work")
    #expect(
      app.environment
        == ["TYLER_SOCKET": "/s.sock", "TYLER_CONFIG": "/c.toml", "PATH": "/bin", "EDITOR": "vi"])
  }

  @Test func relativePathsAreMadeAbsoluteAgainstWhereTylerRuns() {
    let app = AppLaunch.nextTo(
      URL(fileURLWithPath: "/bin/tyler"), socketPath: "x.sock",
      environment: ["TYLER_CONFIG": "../conf/tyler.toml"], workingDirectory: "/work/tyler")
    #expect(app.environment["TYLER_SOCKET"] == "/work/tyler/x.sock")
    #expect(app.environment["TYLER_CONFIG"] == "/work/conf/tyler.toml")
  }

  /// `make` builds the bundle from `packaging/Info.plist`; LaunchServices needs these to run it
  /// as a menu bar app whose executable is the `tylerd` that `executablePath` names.
  @Test func theBundlesInfoPlistLaunchesTylerdAsAMenuBarApp() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("packaging/Info.plist"))
    let plist = try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(plist["CFBundleExecutable"] as? String == "tylerd")
    #expect(plist["CFBundlePackageType"] as? String == "APPL")
    #expect(plist["LSUIElement"] as? Bool == true)
  }
}

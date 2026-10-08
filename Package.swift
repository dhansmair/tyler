// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "mwm",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "mwm", targets: ["mwm"]),
    .executable(name: "mwmd", targets: ["mwmd"]),
  ],
  targets: [
    .target(name: "MWMCore"),
    .target(name: "MWMServer", dependencies: ["MWMCore"]),
    .target(name: "MWMClient", dependencies: ["MWMCore"]),
    .executableTarget(name: "mwmd", dependencies: ["MWMCore", "MWMServer"]),
    .executableTarget(name: "mwm", dependencies: ["MWMCore", "MWMClient"]),

    .testTarget(name: "MWMCoreTests", dependencies: ["MWMCore"]),
    .testTarget(name: "MWMServerTests", dependencies: ["MWMCore", "MWMServer", "MWMClient"]),
    .testTarget(name: "MWMClientTests", dependencies: ["MWMCore", "MWMClient"]),
  ]
)

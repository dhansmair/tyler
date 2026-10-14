// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "tyler",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "tyler", targets: ["tyler"]),
    .executable(name: "tylerd", targets: ["tylerd"]),
  ],
  targets: [
    .target(name: "TylerRuntime"),
    .target(name: "TylerCore"),
    .target(name: "TylerConfig", dependencies: ["TylerRuntime", "TylerCore"]),
    .target(
      name: "TylerProtocol",
      dependencies: ["TylerRuntime", "TylerCore", "TylerConfig"]),
    .target(
      name: "TylerServer",
      dependencies: [
        "TylerRuntime", "TylerCore", "TylerConfig", "TylerProtocol",
      ]),
    .target(
      name: "TylerPlatform",
      dependencies: [
        "TylerRuntime", "TylerCore", "TylerConfig", "TylerProtocol",
        "TylerServer",
      ]),
    .target(
      name: "TylerIndicators",
      dependencies: [
        "TylerRuntime", "TylerCore", "TylerConfig", "TylerProtocol",
      ]),
    .target(
      name: "TylerClient",
      dependencies: ["TylerRuntime", "TylerCore", "TylerProtocol"]),
    .executableTarget(
      name: "tylerd",
      dependencies: [
        "TylerRuntime", "TylerCore", "TylerConfig", "TylerProtocol",
        "TylerServer",
        "TylerPlatform", "TylerIndicators",
      ]),
    .executableTarget(
      name: "tyler",
      dependencies: ["TylerRuntime", "TylerProtocol", "TylerClient"]),

    // What the server test targets share: the fakes and ManagerHarness.
    .target(
      name: "TylerTestSupport",
      dependencies: [
        "TylerRuntime", "TylerCore", "TylerConfig", "TylerProtocol",
        "TylerServer",
      ],
      path: "Tests/TylerTestSupport"),

    .testTarget(name: "TylerRuntimeTests", dependencies: ["TylerRuntime"]),
    .testTarget(name: "TylerCoreTests", dependencies: ["TylerCore"]),
    .testTarget(
      name: "TylerConfigTests",
      dependencies: ["TylerRuntime", "TylerCore", "TylerConfig"]),
    .testTarget(
      name: "TylerProtocolTests",
      dependencies: [
        "TylerRuntime", "TylerCore", "TylerConfig", "TylerProtocol",
      ]),
    .testTarget(
      name: "TylerServerTests",
      dependencies: [
        "TylerRuntime", "TylerCore", "TylerConfig", "TylerProtocol",
        "TylerServer",
        "TylerClient", "TylerTestSupport",
      ]),
    .testTarget(
      name: "TylerScenarioTests",
      dependencies: [
        "TylerRuntime", "TylerCore", "TylerConfig", "TylerProtocol", "TylerServer",
        "TylerClient", "TylerTestSupport",
      ]),
    .testTarget(
      name: "TylerPlatformTests",
      dependencies: [
        "TylerRuntime", "TylerCore", "TylerServer", "TylerPlatform", "TylerTestSupport",
      ]),
    .testTarget(
      name: "TylerIndicatorsTests",
      dependencies: [
        "TylerRuntime", "TylerCore", "TylerConfig", "TylerProtocol",
        "TylerIndicators",
      ]),
    .testTarget(
      name: "TylerClientTests",
      dependencies: [
        "TylerRuntime", "TylerCore", "TylerProtocol", "TylerClient",
      ]),
  ]
)

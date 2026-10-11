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
    .target(name: "TylerCore"),
    .target(name: "TylerServer", dependencies: ["TylerCore"]),
    .target(name: "TylerPlatform", dependencies: ["TylerCore", "TylerServer"]),
    .target(name: "TylerIndicators", dependencies: ["TylerCore"]),
    .target(name: "TylerClient", dependencies: ["TylerCore"]),
    .executableTarget(
      name: "tylerd",
      dependencies: ["TylerCore", "TylerServer", "TylerPlatform", "TylerIndicators"]),
    .executableTarget(name: "tyler", dependencies: ["TylerCore", "TylerClient"]),

    .testTarget(name: "TylerCoreTests", dependencies: ["TylerCore"]),
    .testTarget(
      name: "TylerServerTests", dependencies: ["TylerCore", "TylerServer", "TylerClient"]),
    .testTarget(name: "TylerIndicatorsTests", dependencies: ["TylerCore", "TylerIndicators"]),
    .testTarget(name: "TylerClientTests", dependencies: ["TylerCore", "TylerClient"]),
  ]
)

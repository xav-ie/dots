// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "car-edit",
  platforms: [.macOS(.v13)],
  targets: [
    .systemLibrary(
      name: "CoreUIBridge",
      path: "Sources/CoreUIBridge"
    ),
    .executableTarget(
      name: "car-edit",
      dependencies: ["CoreUIBridge"],
      linkerSettings: [
        .unsafeFlags(["-F", "/System/Library/PrivateFrameworks"])
      ]
    ),
  ]
)

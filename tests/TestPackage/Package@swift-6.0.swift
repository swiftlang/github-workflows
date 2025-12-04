// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "TestPackage",
  targets: [
    .target(
      name: "Target1"
    ),
    .target(
      name: "Target2",
      dependencies: [
        "Target1"
      ]
    ),
    .testTarget(
      name: "Target1Tests",
      dependencies: ["Target1"]
    ),
  ]
)

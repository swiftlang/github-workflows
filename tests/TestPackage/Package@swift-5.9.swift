// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "TestPackage",
  products: [
    // Named after a target: the Cxx interop check imports each library product by name.
    .library(name: "Target1", targets: ["Target1"])
  ],
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

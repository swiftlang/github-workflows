// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MatrixGeneratorValidator",
  targets: [
    .target(name: "MatrixTestSupport"),
    .testTarget(
      name: "MatrixGeneratorTests",
      dependencies: ["MatrixTestSupport"]
    ),
  ]
)

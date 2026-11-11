// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "matrix-generator",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "generate-matrix", targets: ["generate-matrix"])
  ],
  targets: [
    .executableTarget(name: "generate-matrix"),
    .target(name: "MatrixTestSupport", path: "Tests/MatrixTestSupport"),
    .testTarget(
      name: "MatrixGeneratorTests",
      dependencies: ["MatrixTestSupport"]
    ),
  ],
  swiftLanguageModes: [.v5]
)

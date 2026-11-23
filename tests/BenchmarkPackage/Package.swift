// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "BenchmarkPackage",
  platforms: [
    .macOS("14")
  ],
  dependencies: [
    .package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.29.11")
  ],
  targets: [
    .executableTarget(
      name: "FixtureBenchmarks",
      dependencies: [
        .product(name: "Benchmark", package: "package-benchmark")
      ],
      path: "Benchmarks/FixtureBenchmarks",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    )
  ]
)

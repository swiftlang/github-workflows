//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Benchmark

// Allocates nothing, so its threshold is the same on every platform and toolchain.
let benchmarks: @Sendable () -> Void = {
  Benchmark(
    "NoOp",
    configuration: .init(metrics: [.mallocCountTotal])
  ) { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(0)
    }
  }
}

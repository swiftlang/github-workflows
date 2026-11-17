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

import Foundation

/// A machine an entry runs on: the labels that select it, and what it contributes to an
/// entry's name when its group runs on more than one.
struct Runner {
  /// The distribution GitHub's Ubuntu runners run, which is what `linux_os` defaults to: a
  /// job on any other one needs a container image.
  static let ubuntuDistribution = "noble"

  var labels: [String]
  var name: String

  /// The GitHub Ubuntu runner for an architecture.
  static func ubuntu(architecture: String) -> Runner {
    Runner(labels: [architecture == "aarch64" ? "ubuntu-24.04-arm" : "ubuntu-24.04"], name: architecture)
  }

  /// A Windows runner, which the label that selects it also names.
  static func windows(label: String) -> Runner {
    Runner(labels: [label], name: label)
  }

  /// A machine from the self-hosted macOS runners, in one of their pools if the organization
  /// splits them into pools. A pool label no runner carries leaves the job waiting forever,
  /// so an empty pool adds none.
  static func macOS(os: String, architecture: String, pool: String) -> Runner {
    let poolLabels = pool.isEmpty ? [] : [pool]
    return Runner(labels: ["self-hosted", "macos", os, architecture] + poolLabels, name: os)
  }
}

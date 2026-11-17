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

/// The self-hosted macOS machines a group's entries run on.
struct MacOSMachines {
  var operatingSystems: [String]
  var architecture: String
  var pool: String

  /// The machines the entries fan out over.
  var runners: [Runner] {
    self.operatingSystems.map { Runner.macOS(os: $0, architecture: self.architecture, pool: self.pool) }
  }

  /// The machines one swiftly toolchain runs on: an entry naming its own OS runs there alone,
  /// and on the architecture it names.
  func runners(for toolchain: SwiftlyToolchain) -> [Runner] {
    let operatingSystems = toolchain.osVersion.map { [$0] } ?? self.operatingSystems
    return operatingSystems.map {
      Runner.macOS(os: $0, architecture: toolchain.architecture ?? self.architecture, pool: self.pool)
    }
  }
}

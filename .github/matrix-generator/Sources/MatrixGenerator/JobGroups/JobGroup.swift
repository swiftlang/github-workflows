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

/// One group of jobs the matrix can hold: the entries one enable turns on.
protocol JobGroup {
  var settings: JobGroupSettings { get }
  /// In the order the jobs come out in.
  var entries: [MatrixEntry] { get }
  /// Fails on a configuration that would drop a job the caller asked for from this group.
  func validate(against minimum: MinimumVersion)
}

extension JobGroup {
  /// The checks every group makes.
  func validateSettings(against minimum: MinimumVersion) {
    self.settings.validateCommandVersions()
    self.settings.validateReplaceableCommand()
    self.settings.validateRunnableVersions(minimum)
  }

  func validate(against minimum: MinimumVersion) {
    self.validateSettings(against: minimum)
  }
}

/// What a job group fans out over.
enum VersionAxis {
  /// A Swift version list, named by this input.
  case list(input: String)
  /// Swiftly-managed toolchains rather than a version list, named by this input, so a label
  /// has no versions to select from.
  case toolchains(input: String)

  /// The input a message names, so the caller knows which knob to turn.
  var inputName: String {
    switch self {
    case .list(let input), .toolchains(let input): return input
    }
  }
}

/// Where a job group's command comes from.
enum CommandSource {
  /// The caller names it, in the input given, so a per-version `command:` override can replace
  /// it.
  case input(name: String)
  /// The command is the check itself rather than a place to run one, so an override replacing
  /// it would leave the job named for something it no longer does.
  case fixed

  /// The input a message names, or nil when the command is the check itself.
  var inputName: String? {
    switch self {
    case .input(let name): return name
    case .fixed: return nil
    }
  }
}

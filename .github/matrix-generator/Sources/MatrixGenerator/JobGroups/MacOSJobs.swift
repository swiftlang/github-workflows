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

/// The macOS entries: one pass over the Xcode list, which names Xcodes, and one over the
/// Swift list, which names Swift versions. A label's versions select from whichever list holds
/// them, so a label naming an Xcode contributes nothing to the Swift pass.
struct MacOSJobs: JobGroup {
  var settings: JobGroupSettings
  var minimum: MinimumVersion
  var releases: SwiftReleases
  var flags: SwiftFlags
  var setupCommand: String
  var environment: JSONValue
  var machines: MacOSMachines
  var targets: [XcodeTarget]
  var debugOutput: Bool
  /// What the Xcode pass's entry names carry before the version. The Swift pass takes the
  /// group's own prefix.
  let xcodeNamePrefix = "macOS Xcode"

  /// The Xcodes a label may select, which the group's Xcode list names.
  private var xcodeVersions: [String] { self.settings.versionsExemptFromMinimum }

  var entries: [MatrixEntry] {
    self.machines.runners.flatMap { runner in
      self.pass(self.xcodeVersions, on: runner, namePrefix: self.xcodeNamePrefix, namesXcode: true)
        + self.pass(
          self.settings.versions,
          on: runner,
          namePrefix: self.settings.namePrefix,
          namesXcode: false
        )
    }
  }

  private func pass(
    _ versions: [String],
    on runner: Runner,
    namePrefix: String,
    namesXcode: Bool
  ) -> [MatrixEntry] {
    if versions.isEmpty { return [] }
    return self.settings.commands.flatMap { variant in
      // The Xcode list names Xcodes, which the minimum Swift version does not order.
      variant.versions(among: versions).filter { namesXcode || self.minimum.admits($0) }.map { version in
        MatrixEntry(
          platform: .macOS,
          name: self.settings.name(
            "\(namePrefix) \(version)",
            self.machines.runners.count > 1 ? runner.name : nil,
            for: variant
          ),
          runner: runner.labels,
          xcodeBuild: MatrixEntry.XcodeBuild(
            swiftVersion: namesXcode ? nil : self.releases.resolvedVersion(for: version),
            xcodeVersion: namesXcode ? version : nil,
            targets: self.targets,
            debugOutput: self.debugOutput
          ),
          setupCommand: self.setupCommand,
          command: self.settings.overrides.command(for: version) ?? variant.command,
          commandArguments: self.flags.arguments(for: version),
          env: self.environment
        )
      }
    }
  }
}

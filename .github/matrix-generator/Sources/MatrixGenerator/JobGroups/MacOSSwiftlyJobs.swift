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

/// The macOS entries driven by a swiftly-managed toolchain, which fan out over the toolchains
/// rather than a version list.
struct MacOSSwiftlyJobs: JobGroup {
  var settings: JobGroupSettings
  var flags: SwiftFlags
  var setupCommand: String
  var environment: JSONValue
  var machines: MacOSMachines
  var toolchains: [SwiftlyToolchain]

  func validate(against minimum: MinimumVersion) {
    self.validateSettings(against: minimum)
    // Skipping the entry would drop a job from a run that still reports success, which is how
    // a misspelled key goes unnoticed.
    for toolchain in self.toolchains
    where toolchain.xcodeVersion.isEmpty || toolchain.swiftlyToolchain.isEmpty {
      fatal(
        """
        macos_swiftly_toolchains entry needs both xcode_version and swiftly_toolchain: \
        xcode_version "\(toolchain.xcodeVersion)", swiftly_toolchain "\(toolchain.swiftlyToolchain)"
        """
      )
    }
  }

  var entries: [MatrixEntry] {
    self.toolchains.flatMap { toolchain in
      self.machines.runners(for: toolchain).flatMap { runner in
        self.settings.commands.map { variant in
          MatrixEntry(
            platform: .macOS,
            name: self.settings.name(
              "\(self.settings.namePrefix) \(toolchain.swiftlyToolchain) "
                + "(Xcode \(toolchain.xcodeVersion))",
              self.machines.operatingSystems.count > 1 ? runner.name : nil,
              for: variant
            ),
            runner: runner.labels,
            xcodeBuild: MatrixEntry.XcodeBuild(
              xcodeVersion: toolchain.xcodeVersion,
              swiftlyToolchain: toolchain.swiftlyToolchain
            ),
            setupCommand: self.setupCommand,
            command: variant.command,
            // A snapshot takes the nightly flags, as a "nightly-" prefix does elsewhere.
            commandArguments: self.flags.arguments(
              nightly: toolchain.swiftlyToolchain.contains("snapshot")
            ),
            env: self.environment
          )
        }
      }
    }
  }
}

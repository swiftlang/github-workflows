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

/// The FreeBSD entries, which carry a virtual machine and a toolchain URL rather than a
/// `swift_build`.
struct FreeBSDJobs: JobGroup {
  /// The one toolchain published for FreeBSD.
  private static let toolchainURL =
    "https://download.swift.org/tmp-ci-nightly/development/freebsd-14_ci_latest.tar.gz"

  var settings: JobGroupSettings
  var setupCommand: String
  var osVersions: [String]
  var buildFlags: String
  var environmentVariables: String

  func validate(against minimum: MinimumVersion) {
    self.validateSettings(against: minimum)
    // One FreeBSD toolchain is published, so a version naming anything else would produce a
    // job labeled for a toolchain it does not install.
    for version in self.settings.versions where version != "nightly-main" {
      fatal("FreeBSD supports only the nightly-main Swift version, not '\(version)'.")
    }
    // The published tarballs are named by major release and only 14 has one, so any other OS
    // version would install a toolchain built for a release the job is not labeled for.
    for osVersion in self.osVersions where osVersion != "14" && !osVersion.hasPrefix("14.") {
      fatal(
        "No Swift toolchain is published for FreeBSD \(osVersion); freebsd_os_versions supports 14 releases."
      )
    }
  }

  var entries: [MatrixEntry] {
    self.osVersions.flatMap { osVersion in
      self.settings.commands.flatMap { variant in
        variant.versions(among: self.settings.versions).map { version in
          MatrixEntry(
            platform: .freeBSD,
            name: self.settings.name(
              "\(self.settings.namePrefix) \(version) - \(osVersion) - x86_64",
              for: variant
            ),
            runner: ["ubuntu-24.04"],
            freeBSDBuild: MatrixEntry.FreeBSDBuild(
              osVersion: osVersion,
              swiftVersion: version,
              swiftURL: FreeBSDJobs.toolchainURL,
              buildFlags: self.buildFlags,
              envVars: self.environmentVariables
            ),
            setupCommand: self.setupCommand,
            command: variant.command,
            commandArguments: [],
            env: .object([:])
          )
        }
      }
    }
  }
}

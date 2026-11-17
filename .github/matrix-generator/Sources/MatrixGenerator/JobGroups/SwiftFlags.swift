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

/// The flags an entry's command runs with, by the kind of toolchain it runs on.
struct SwiftFlags {
  /// What a released toolchain's command takes.
  var release: String
  /// What a nightly toolchain's command takes.
  var nightly: String
  /// What a particular version adds to those.
  var overrides = VersionOverrides()

  /// The same arguments on every toolchain, for a build that takes none of the flags inputs.
  static func always(_ arguments: String) -> SwiftFlags {
    SwiftFlags(release: arguments, nightly: arguments)
  }

  /// The arguments one version's command runs with.
  func arguments(for versionLabel: String) -> [String] {
    let base = self.flags(nightly: VersionLabel(versionLabel).isNightly)
    return self.split("\(base) \(self.overrides.arguments(for: versionLabel) ?? "")")
  }

  /// The arguments for a toolchain that has no version to look an override up by; this is
  /// how a swiftly snapshot takes the nightly flags.
  func arguments(nightly: Bool) -> [String] {
    self.split(self.flags(nightly: nightly))
  }

  private func flags(nightly: Bool) -> String {
    nightly ? self.nightly : self.release
  }

  /// A flags input as the arguments it names. Globbing never happens, so a wildcard reaches
  /// the runner as the argument the caller wrote.
  private func split(_ flags: String) -> [String] {
    flags.split(whereSeparator: \.isWhitespace).map(String.init)
  }
}

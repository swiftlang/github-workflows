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

/// A version label and the forms upstream publishes it under.
struct Toolchain {
  /// The version the caller's label names, such as `6.3`, or the `nightly-release` or
  /// `nightly-main` label itself.
  let version: String
  /// The branch spelling upstream publishes the next release's nightly under, which
  /// `nightly-release` is an alias for, if the caller gave one.
  let nightlyBranch: String?

  init(label: String, releases: SwiftReleases) {
    self.version = releases.resolvedVersion(for: label)
    self.nightlyBranch = releases.nightlyBranch
  }

  /// The Docker tag infix, the Windows installer script suffix, and the argument
  /// install-and-build-with-sdk.sh takes.
  var resolved: String {
    guard let nightlyBranch = self.nightlyBranch else {
      if self.version == "nightly-release" {
        fatal("swift_nightly_release is not set, so 'nightly-release' has no branch to name.")
      }
      return self.version
    }
    let alias = "nightly-\(nightlyBranch)"
    return self.version == "nightly-release" || self.version == alias ? alias : self.version
  }

  /// The swiftly selector. The branch token names the release snapshot's own directory under
  /// dev/, and swiftly's release-snapshot grammar takes it whole, so it is passed through.
  var swiftly: String {
    guard VersionLabel(self.resolved).isNightly else { return self.resolved }
    let branch = String(self.resolved.dropFirst("nightly-".count))
    return branch == "main" ? "main-snapshot" : "\(branch)-snapshot"
  }

  /// The image this toolchain runs in on a distribution. Upstream publishes the nightlies
  /// under their own repository, so a nightly is not tagged like a release.
  func image(distribution: String) -> String {
    VersionLabel(self.resolved).isNightly
      ? "swiftlang/swift:\(self.resolved)-\(distribution)"
      : "swift:\(self.resolved)-\(distribution)"
  }
}

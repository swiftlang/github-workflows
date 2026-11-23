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

/// The releases a run was given, which the labels that name one by position resolve against.
struct SwiftReleases {
  /// The release `current` names, such as `6.4`, if the caller gave one.
  let currentRelease: String?
  /// The branch spelling upstream publishes the next release's nightly under, such as `6.4.x`,
  /// which `nightly-release` is an alias for, if the caller gave one.
  let nightlyBranch: String?

  /// The version a label names: `current`, `current-1` and `current-2` count back from the
  /// current release, and anything else is already a version.
  func resolvedVersion(for label: String) -> String {
    switch VersionLabel(label) {
    case .nightly, .explicit:
      return label

    case .release(let offset):
      guard let currentRelease = self.currentRelease else {
        fatal("swift_current_release is not set, so '\(label)' has no release to count back from.")
      }
      guard let release = SwiftVersion(majorMinor: currentRelease) else {
        fatal(
          """
          swift_current_release must be a major.minor version such as 6.4, but got: '\(currentRelease)'
          """
        )
      }
      guard release.minor >= offset else {
        fatal("'\(label)' counts back past the first minor release of Swift \(release.major).")
      }
      return "\(release.major).\(release.minor - offset)"
    }
  }

  /// Where a label falls among the released versions, for ordering it.
  func ordered(_ label: String) -> SwiftVersion {
    SwiftVersion.inVersionList(self.resolvedVersion(for: label))
  }
}

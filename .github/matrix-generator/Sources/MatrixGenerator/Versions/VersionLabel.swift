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

/// What a version list entry names.
enum VersionLabel {
  /// `current`, `current-1` or `current-2`: a release counted back from the current one.
  case release(offset: Int)
  /// A nightly such as `nightly-main`.
  case nightly(String)
  /// A version written out, such as `6.0`.
  case explicit(String)

  init(_ text: String) {
    if text.hasPrefix("nightly-") {
      self = .nightly(text)
      return
    }
    guard text == "current" || text.hasPrefix("current-") else {
      self = .explicit(text)
      return
    }
    let offset = text == "current" ? 0 : Int(text.dropFirst("current-".count))
    guard let offset, (0...2).contains(offset) else {
      fatal(
        """
        '\(text)' is not a Swift version label. Relative labels are current, current-1 and current-2; \
        write the version to name an older one.
        """
      )
    }
    self = .release(offset: offset)
  }

  /// Whether the label names a nightly toolchain, which takes the nightly flags and is always
  /// kept by the minimum-version filter.
  var isNightly: Bool {
    switch self {
    case .nightly: return true
    case .release, .explicit: return false
    }
  }
}

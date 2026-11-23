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

/// A released Swift version, ordered by its components.
struct SwiftVersion: Comparable {
  private let components: [Int]

  init?(_ text: String) {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...3).contains(parts.count) else { return nil }
    let numbers = parts.compactMap { Int($0) }
    guard numbers.count == parts.count else { return nil }
    self.components = numbers + Array(repeating: 0, count: 3 - numbers.count)
  }

  /// A `major.minor` version, which a release is named by.
  init?(majorMinor text: String) {
    guard text.split(separator: ".", omittingEmptySubsequences: false).count == 2 else { return nil }
    self.init(text)
  }

  var major: Int { self.components[0] }
  var minor: Int { self.components[1] }

  static func < (first: SwiftVersion, second: SwiftVersion) -> Bool {
    first.components.lexicographicallyPrecedes(second.components)
  }

  /// A version list entry, which is a number or a nightly label and nothing else. A label
  /// this cannot order would otherwise be silently kept or dropped.
  static func inVersionList(_ label: String) -> SwiftVersion {
    guard let version = SwiftVersion(label) else {
      fatal(
        """
        Cannot compare '\(label)' as a version. A Swift version list takes numbers like 6.3, or a \
        nightly- label; '\(label)' is neither.
        """
      )
    }
    return version
  }
}

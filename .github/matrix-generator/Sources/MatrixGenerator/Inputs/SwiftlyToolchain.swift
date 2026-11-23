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

/// A macOS entry driven by a swiftly-managed toolchain rather than the Xcode that ships one.
struct SwiftlyToolchain: InputElement {
  var xcodeVersion = ""
  var swiftlyToolchain = ""
  /// An entry naming its own OS runs there alone; the rest fan out over macos_os.
  var osVersion: String?
  var architecture: String?

  init(xcodeVersion: String, swiftlyToolchain: String) {
    self.xcodeVersion = xcodeVersion
    self.swiftlyToolchain = swiftlyToolchain
  }

  init(element: JSONValue, text: String) {
    let known = ["xcode_version", "swiftly_toolchain", "os_version", "arch"]
    let unknown = Set(element.asObject?.keys ?? [:].keys).subtracting(known).sorted()
    if !unknown.isEmpty {
      fatal(
        """
        macos_swiftly_toolchains includes unknown keys: \(unknown.joined(separator: ", ")). \
        An entry takes xcode_version, swiftly_toolchain, os_version and arch.
        """
      )
    }
    self.xcodeVersion = element["xcode_version"]?.text ?? ""
    self.swiftlyToolchain = element["swiftly_toolchain"]?.text ?? ""
    self.osVersion = element["os_version"]?.text
    self.architecture = element["arch"]?.text
  }
}

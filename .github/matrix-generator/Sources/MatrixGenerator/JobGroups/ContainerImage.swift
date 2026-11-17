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

/// A Swift container image an entry runs in, and what the Docker inputs add to it.
struct ContainerImage {
  /// The only Windows runner a Swift container image is published for.
  static let windowsRunner = "windows-2022"

  /// The Swift Windows Server image, which is tagged like a distribution.
  static let windows = ContainerImage(distribution: "windowsservercore-ltsc2022")

  /// The part of the image tag that follows the toolchain, such as `noble`.
  var distribution: String
  /// A Dockerfile that extends the image, when the caller named one.
  var dockerfile: String?
  var capabilities: [String]?
  var securityOptions: [String]?

  /// The image one toolchain runs in.
  func container(_ toolchain: Toolchain) -> MatrixEntry.SwiftBuild.Container {
    MatrixEntry.SwiftBuild.Container(
      image: toolchain.image(distribution: self.distribution),
      dockerfile: self.dockerfile,
      capabilities: self.capabilities,
      securityOptions: self.securityOptions
    )
  }
}

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

extension String {
  /// The text without the newlines it ends with, which is how a command reaches the runner:
  /// a YAML block scalar ends with one, and `swift build\n` is the command `swift build`.
  var trimmingTrailingNewlines: String {
    var text = self
    while text.hasSuffix("\n") { text.removeLast() }
    return text
  }
}

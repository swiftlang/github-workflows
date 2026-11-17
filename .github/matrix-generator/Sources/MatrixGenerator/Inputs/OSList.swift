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

/// An input naming one OS, or a list of them.
///
/// Only a list is taken from the parse: a single value is used exactly as it was written,
/// because YAML reads `24.10` as the number 24.1 and drops everything after a ` #`, and no
/// image is tagged 6.3-24.1.
struct OSList: InputDecodable, ExpressibleByStringLiteral {
  var names: [String]

  init(_ name: String) {
    self.names = [name]
  }

  init(stringLiteral name: String) {
    self.init(name)
  }

  init(input text: String, name: String) {
    guard let parsed = Parsed(text) else {
      fatal("\(name) is not valid JSON or YAML: \(text)")
    }
    if parsed.isList {
      self.names = [String](input: text, name: name)
    } else if parsed.isMap {
      fatal("\(name) must be a name or a list of them, such as [\"a\", \"b\"], but got: \(text)")
    } else {
      self.names = [text]
    }
  }
}

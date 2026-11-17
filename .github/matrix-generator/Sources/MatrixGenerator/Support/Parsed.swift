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

/// A value as yq read it: its YAML tag, and - for a map - its members in the order they were
/// written, a key written twice included.
struct Parsed: Decodable {
  struct Member: Decodable {
    var key: String
    var value: JSONValue
  }

  private var tag: String
  var value: JSONValue
  /// One element holding the members when the value is a map, and empty otherwise: the filter
  /// uses `select`, which yields one result or none, and yq has no conditional that returns
  /// a value either way. `mapMembers` is what a caller reads.
  private var members: [[Member]]
  /// The same, for a list's elements as they were written.
  private var elements: [[String]]

  var isList: Bool { self.tag == "!!seq" }
  var isMap: Bool { self.tag == "!!map" }
  var isCollection: Bool { self.isList || self.isMap }
  var mapMembers: [Member] { self.members.first ?? [] }
  /// A list's elements as text. YAML reads `24.10` as the number 24.1, and no image is tagged
  /// 6.3-24.1, so the token the caller wrote is what a name is taken from.
  var listElements: [String] { self.elements.first ?? [] }

  /// Reads a value the way yq does. Nil means the value is neither YAML nor JSON; two callers
  /// distinguish that from a value of the wrong shape.
  init?(_ text: String) {
    let result = yq.run(["-o=json", "-I=0", Parsed.filter], input: text)
    guard result.worked else { return nil }
    do {
      self = try JSONDecoder().decode(Parsed.self, from: result.standardOutput)
    } catch {
      fatal("yq produced JSON this generator could not read: \(error)")
    }
  }

  /// A value's shape, its members and its elements in one pass. `tostring` is applied to the
  /// copies in `members` and `elements` and to nothing else, so `value` keeps the original
  /// types: `versions: [6.3]` stays a number for the label's settings check to reject it.
  private static let filter = """
    {"tag": tag, "value": ., \
    "members": [select(tag == "!!map") | to_entries | map({"key": (.key | tostring), "value": .value})], \
    "elements": [select(tag == "!!seq") | map(tostring)]}
    """
}

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

/// A value of any shape, which is what an input carries before its shape is known.
enum JSONValue: Codable {
  case null
  case bool(Bool)
  case integer(Int)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    // Each `try?` asks "is it this shape," so a failure is the answer rather than an error
    // to swallow. The order is the one JSON allows: an integer also decodes as a double.
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let items): try container.encode(items)
    case .object(let members): try container.encode(members)
    }
  }

  subscript(key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members[key]
  }

  var asObject: [String: JSONValue]? {
    guard case .object(let members) = self else { return nil }
    return members
  }

  var asString: String? {
    guard case .string(let text) = self else { return nil }
    return text
  }

  var asBool: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }

  var asArray: [JSONValue]? {
    guard case .array(let items) = self else { return nil }
    return items
  }

  /// The value, or nil when it carried nothing: an absent setting and an explicit null are
  /// the same answer.
  var nonNull: JSONValue? { self.isNull ? nil : self }

  var isNull: Bool {
    guard case .null = self else { return false }
    return true
  }

  /// The value as one line of text, the way `jq -r` writes it. A version list written
  /// `[6.3]` still names the version `6.3`.
  var text: String {
    self.asString ?? self.description
  }
}

extension JSONValue: CustomStringConvertible {
  /// The value as JSON on one line, which is how a message quotes back what a caller wrote.
  var description: String {
    switch self {
    case .null: return "null"
    case .bool(let value): return value ? "true" : "false"
    case .integer(let value): return String(value)
    case .number(let value): return String(value)
    case .string(let text): return JSONValue.quoted(text)
    case .array(let items): return "[" + items.map(\.description).joined(separator: ",") + "]"

    case .object(let members):
      // Sorted so a message quoting a caller's value back reads the same on every run: a
      // dictionary has no order of its own.
      let written = members.sorted { $0.key < $1.key }
      return "{" + written.map { "\(JSONValue.quoted($0.key)):\($0.value)" }.joined(separator: ",") + "}"
    }
  }

  static func quoted(_ text: String) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": result += "\\\""
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case "\t": result += "\\t"
      case _ where scalar.value < 0x20: result += String(format: "\\u%04x", scalar.value)
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result + "\""
  }
}

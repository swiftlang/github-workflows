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

/// An input. A value that carries nothing - unset, or the empty string Actions passes for an
/// input a caller left out - takes the declared default, which is already the parsed form.
@propertyWrapper
struct Input<Value: InputDecodable> {
  var wrappedValue: Value

  init(wrappedValue defaultValue: Value, _ variable: String) {
    self.wrappedValue = Input.read(variable, default: defaultValue)
  }

  /// What an environment variable carries, or the default when it carries nothing.
  static func read(_ variable: String, default defaultValue: Value) -> Value {
    let text = ProcessInfo.processInfo.environment[variable] ?? ""
    return text.isEmpty ? defaultValue : Value(input: text, name: variable.lowercased())
  }
}

/// A value an input can carry. The conformance is where that shape's rules live: an input
/// carrying the wrong shape fails the run rather than contributing nothing.
protocol InputDecodable {
  init(input text: String, name: String)
}

/// An element of a list input.
protocol InputElement {
  /// - Parameters:
  ///   - element: the element as it parsed.
  ///   - text: the element as it was written, which is not the same for a number.
  init(element: JSONValue, text: String)
}

extension String: InputDecodable, InputElement {
  init(input text: String, name: String) { self = text }
  init(element: JSONValue, text: String) { self = text }
}

extension Int: InputDecodable {
  /// A count that is not a whole number would be dropped to a default the caller did not choose.
  init(input text: String, name: String) {
    guard let value = Int(text.trimmingCharacters(in: .whitespaces)), value >= 0 else {
      fatal("\(name) must be a whole number, but got: \(text)")
    }
    self = value
  }
}

extension Bool: InputDecodable {
  /// Anything but `true` is off, which is what an unset input is.
  init(input text: String, name: String) { self = text == "true" }
}

extension Array: InputDecodable where Element: InputElement {
  /// A value of another shape would contribute no entries: the platform would be absent from
  /// a run that still reports success.
  init(input text: String, name: String) {
    guard let parsed = Parsed(text) else {
      fatal("\(name) is not valid JSON or YAML: \(text)")
    }
    guard let items = parsed.value.asArray else {
      fatal("\(name) must be a list, such as [\"a\", \"b\"], but got: \(text)")
    }
    self = zip(items, parsed.listElements).map(Element.init(element:text:))
  }
}

extension JSONValue: InputDecodable {
  /// An input passed through to the entry, such as an environment block.
  init(input text: String, name: String) {
    guard let parsed = Parsed(text) else {
      fatal("\(name) is not valid JSON or YAML: \(text)")
    }
    guard parsed.isMap || parsed.value.isNull else {
      fatal("\(name) must be a map of name to value, such as {FOO: bar}, but got: \(text)")
    }
    self = parsed.value.isNull ? .object([:]) : parsed.value
  }
}

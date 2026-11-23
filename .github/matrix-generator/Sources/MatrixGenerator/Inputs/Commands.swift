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

/// What a `*_command` input names: one command, or a map of label to command.
///
///   linux_command: swift test
///
///   linux_command: |
///     test: swift test
///     release:
///       command: swift build -c release
///       versions: ["6.3"]
struct Commands: InputDecodable, ExpressibleByStringLiteral {
  /// One command a group runs, and the label its jobs carry.
  struct Variant {
    var label: String
    var command: String
    var versionLabels: [String]?

    init(label: String, command: String, versionLabels: [String]?) {
      self.label = label
      self.command = command.trimmingTrailingNewlines
      self.versionLabels = versionLabels
    }

    /// The versions this variant runs on, in the group's own order rather than the label's.
    func versions(among available: [String]) -> [String] {
      guard let versionLabels = self.versionLabels else { return available }
      return available.filter(versionLabels.contains)
    }
  }

  private var variants: [Variant]

  /// The label leading an entry's job name, which is nothing when the group runs one command:
  /// entry names are required status checks in adopting repositories.
  func nameLabel(for variant: Variant) -> String? {
    self.count > 1 ? variant.label : nil
  }

  init(_ command: String) {
    self.variants = [Variant(label: "", command: command, versionLabels: nil)]
  }

  init(stringLiteral command: String) {
    self.init(command)
  }

  /// The parse only classifies. Anything but a map of labels is the command itself, taken
  /// byte for byte - including a value that is not YAML at all, such as
  /// `[ -f x ] && swift build`.
  ///
  /// A shell command can parse as a map: `swift test --filter Foo: Bar` yields one keyed on
  /// everything before the colon. Requiring every key to be a label leaves only
  /// `<word>: <rest>` ambiguous, and that names a program whose name ends in a colon, so it
  /// is not a command anyone would have run.
  init(input text: String, name: String) {
    self.variants =
      Commands.labeled(text, name: name) ?? [Variant(label: "", command: text, versionLabels: nil)]
  }

  /// The variants a map of labels names, or nil when the value is the command itself.
  private static func labeled(_ text: String, name: String) -> [Variant]? {
    guard let parsed = Parsed(text) else { return nil }
    if parsed.isList {
      fatal(
        """
        \(name) takes a command, or a map of label to command such as {test: swift test}, but got a \
        list: \(text)
        """
      )
    }
    let members = parsed.mapMembers
    if members.isEmpty || members.contains(where: { !Commands.isLabel($0.key) }) { return nil }
    // A label written twice would run one command of the two the caller named, and under the
    // bare name, since one command earns no label.
    guard Set(members.map(\.key)).count == members.count else {
      fatal("\(name) names a label more than once: \(text)")
    }

    // A label carrying anything else - a number, a misspelled key, a blank command, an empty
    // version list - would leave the job running the group's default command under a name
    // that says otherwise, or produce no job for that label at all.
    let malformed = members.filter { settings(of: $0.value) == nil }
    guard malformed.isEmpty else {
      let reported = malformed.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
      fatal(
        """
        \(name) takes each label's command as a non-blank string, or a map of command and a non-empty \
        versions list, but got: \(reported)
        """
      )
    }

    return members.compactMap { member in
      settings(of: member.value).map {
        Variant(label: member.key, command: $0.command, versionLabels: $0.versions)
      }
    }
  }

  /// The command and versions a label carries, or nil when it carries no usable command.
  private static func settings(of value: JSONValue) -> (command: String, versions: [String]?)? {
    if let command = value.asString {
      return command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : (command, nil)
    }
    guard case .object(let settings) = value,
      Set(settings.keys).subtracting(["command", "versions"]).isEmpty,
      let command = settings["command"]?.asString,
      !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return nil
    }
    guard let listed = settings["versions"]?.nonNull else { return (command, nil) }
    guard let versions = listed.asArray, !versions.isEmpty,
      versions.allSatisfy({ $0.asString != nil })
    else {
      return nil
    }
    return (command, versions.map(\.text))
  }

  /// A label leads the job name, so it is a word. That is also what keeps a shell command
  /// YAML reads as a map from being mistaken for one.
  private static func isLabel(_ text: String) -> Bool {
    guard let first = text.first, first.isASCII, first.isLetter || first.isNumber else { return false }
    return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) }
  }
}

/// One command each, and never none: a value that is not a map of labels is itself the
/// command, so there is always something to run.
extension Commands: RandomAccessCollection {
  var startIndex: Int { self.variants.startIndex }
  var endIndex: Int { self.variants.endIndex }
  subscript(position: Int) -> Variant { self.variants[position] }
}

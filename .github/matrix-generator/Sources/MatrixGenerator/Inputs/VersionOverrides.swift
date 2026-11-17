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

/// What a `*_version_overrides` input carries: for one version, arguments to add, or a
/// command to replace.
///
///   linux_version_overrides: |
///     6.2: -Xswiftc -warnings-as-errors
///     nightly-main:
///       command: swift build
///       arguments: --explicit-target-dependency-import-check error
struct VersionOverrides: InputDecodable {
  /// What one version's key carries.
  private struct Override {
    var version: String
    var arguments: String?
    var command: String?

    init(version: String, arguments: String?, command: String?) {
      self.version = version
      self.arguments = arguments
      self.command = command?.trimmingTrailingNewlines
    }
  }

  /// The input these were read from, which a message names so the caller knows which knob to
  /// turn. Empty for the default, which carries no overrides for a message to be about.
  private(set) var name = ""
  private var overrides: [Override] = []

  /// The key whose arguments a version takes unless its own key names some.
  static let defaultKey = "default"

  var isEmpty: Bool { self.overrides.isEmpty }
  /// The versions the keys name, which `default` is not one of.
  var versions: [String] { self.overrides.map(\.version).filter { $0 != Self.defaultKey } }

  init() {}

  /// What a version's override adds to the flags, if it names any: its own, or else those of
  /// `default`. A version key replaces `default` for the fields it names and leaves it the rest.
  func arguments(for versionLabel: String) -> String? {
    self.override(for: versionLabel)?.arguments ?? self.override(for: Self.defaultKey)?.arguments
  }

  /// The command a version's override replaces the group's with, if it names one.
  func command(for versionLabel: String) -> String? {
    self.override(for: versionLabel)?.command
  }

  /// The last override written for a version, which is what jq would do reading these into an
  /// object. The members are kept in the order they were written so that a repeated key can be
  /// seen.
  private func override(for versionLabel: String) -> Override? {
    self.overrides.last { $0.version == versionLabel }
  }

  /// The versions this replaces the command for, of those a group runs. A key naming a version
  /// the group's own list does not hold reaches none of its entries.
  func versionsReplacingTheCommand(among groupVersions: [String]) -> [String] {
    self.overrides.filter { $0.command != nil && groupVersions.contains($0.version) }.map(\.version)
  }

  /// The override for a version is read by looking the version up, so a value of any other
  /// shape is absent rather than wrong: the arguments the caller asked for go missing from a
  /// job that still passes, which is how a repository loses warnings-as-errors.
  init(input text: String, name: String) {
    self.name = name
    guard let parsed = Parsed(text) else {
      fatal("\(name) is not valid JSON or YAML: \(text)")
    }
    // A value that carried nothing - blank, or an explicit null - is no overrides rather
    // than a malformed map.
    if parsed.value.isNull { return }
    // Arguments written alone are the default arguments.
    if !parsed.isMap, let arguments = parsed.value.asString {
      self.overrides = [Override(version: Self.defaultKey, arguments: arguments, command: nil)]
      return
    }
    guard parsed.isMap else {
      fatal(
        """
        \(name) must be a map of version to override, such as {"6.3": "-Xswiftc -warnings-as-errors"}, \
        or the default arguments, but got: \(text)
        """
      )
    }

    let members = parsed.mapMembers
    let notOverrides = members.filter {
      if case .object = $0.value { return false }
      return $0.value.asString == nil
    }
    guard notOverrides.isEmpty else {
      let reported = notOverrides.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
      fatal(
        "\(name) takes the arguments as a string, or a map with command and arguments, but got: \(reported)"
      )
    }

    // A misspelled key inside the map, or a value that is not a string, carries nothing while
    // looking as though it does.
    let malformed = members.filter { member in
      guard case .object(let settings) = member.value else { return false }
      return !Set(settings.keys).subtracting(["arguments", "command"]).isEmpty
        || settings.values.contains { $0.asString == nil }
    }
    guard malformed.isEmpty else {
      let reported = malformed.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
      fatal("\(name) takes command and arguments, each a string, but got: \(reported)")
    }

    // A default command would give every command label the same one.
    if members.contains(where: { $0.key == Self.defaultKey && $0.value["command"] != nil }) {
      fatal("\(name) takes only arguments under '\(Self.defaultKey)'; a command belongs to a version.")
    }

    self.overrides = members.map { member in
      Override(
        version: member.key,
        arguments: member.value.asString ?? member.value["arguments"]?.asString,
        command: member.value["command"]?.asString
      )
    }
  }

  /// Fails when a key names no version any enabled group runs. The arguments it carries are
  /// silently lost otherwise, which is how a version rename drops warnings-as-errors.
  func validateKeys(against runnableVersions: [String]) {
    if self.isEmpty { return }
    // No versions means no enabled group reads these, so a key names nothing because nothing
    // runs. Failing there would take down the platforms that are enabled.
    if runnableVersions.isEmpty {
      log("WARNING: ignoring \(self.name): no enabled job group reads it")
      return
    }
    for key in self.versions where !runnableVersions.contains(key) {
      fatal(
        """
        \(self.name) override key '\(key)' does not match any version in the matrix. Valid keys: \
        \(runnableVersions.joined(separator: " "))
        """
      )
    }
  }
}

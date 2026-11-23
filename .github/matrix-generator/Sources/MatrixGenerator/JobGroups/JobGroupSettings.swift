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

/// What a job group runs, and the inputs a message about it has to name.
struct JobGroupSettings {
  var enableInput: String
  var versionAxis: VersionAxis
  var versions: [String]
  var commandSource: CommandSource
  var commands: Commands
  var overrides = VersionOverrides()
  /// Versions a label may select that the minimum-version filter never sees. Only macOS has
  /// any: its Xcode list names Xcodes rather than Swift versions.
  var versionsExemptFromMinimum: [String] = []
  var namePrefix: String

  var selectableVersions: [String] {
    self.versionsExemptFromMinimum.isEmpty
      ? self.versions
      : Set(self.versions + self.versionsExemptFromMinimum).sorted()
  }

  /// An entry's name: what distinguishes it, led by its command's label.
  ///
  /// An axis with one value contributes nothing, and the label leads rather than trailing the
  /// version: entry names are required status checks in adopting repositories, and a label
  /// after the version would read as part of it.
  func name(_ base: String, _ suffixes: String?..., for variant: Commands.Variant) -> String {
    let name = ([base] + suffixes.compactMap { $0 }).joined(separator: " ")
    guard let label = self.commands.nameLabel(for: variant) else { return name }
    return "\(label) \(name)"
  }
}

extension JobGroupSettings {
  /// Fails when a label selects a version the group does not run: the label contributes no
  /// entries, so the command the caller named is missing from a run that reports success.
  func validateCommandVersions() {
    guard let commandsInput = self.commandSource.inputName else { return }
    switch self.versionAxis {
    case .toolchains(let toolchainsInput):
      // Fanning out over toolchains leaves a label nothing to select from, so the versions it
      // names carry nothing.
      if self.commands.contains(where: { $0.versionLabels != nil }) {
        fatal("\(commandsInput) takes no versions; its toolchains come from \(toolchainsInput).")
      }

    case .list:
      let selectable = self.selectableVersions
      let unmatched = self.commands.flatMap { variant in
        (variant.versionLabels ?? []).filter { !selectable.contains($0) }.map { "\(variant.label): \($0)" }
      }
      guard unmatched.isEmpty else {
        fatal(
          """
          \(commandsInput) selects versions the matrix does not hold: \(unmatched.joined(separator: ", ")). \
          Valid versions: \(selectable.joined(separator: " "))
          """
        )
      }
    }
  }

  /// Fails when a per-version `command:` override has nothing to replace: with more than one
  /// command, honoring it would give every label the same one and leave jobs that differ only
  /// in name.
  func validateReplaceableCommand() {
    let replaced = self.overrides.versionsReplacingTheCommand(among: self.versions)
    if replaced.isEmpty { return }
    guard let commandsInput = self.commandSource.inputName else {
      fatal(
        """
        \(self.overrides.name) replaces the command for \(replaced.joined(separator: ", ")), which \
        "\(self.namePrefix)" also runs. Its command is the check itself, so replacing it would leave the \
        job named for something it no longer does. Drop the command from the override, or take that \
        version out of this group's version list.
        """
      )
    }
    guard self.commands.count > 1 else { return }
    fatal(
      """
      \(self.overrides.name) replaces the command for \(replaced.joined(separator: ", ")), but \
      \(commandsInput) has more than one command configured, so there is no single command to replace. \
      Give that label its own versions instead.
      """
    )
  }

  /// Fails when the minimum-version filter leaves the group, or one of its labels, nothing to
  /// run. Dropping some versions is the filter working; dropping all of them is a job the
  /// caller asked for and did not get, in a run that still reports success.
  func validateRunnableVersions(_ minimum: MinimumVersion) {
    // An empty list is a group given no versions rather than one the filter emptied; the
    // whole-matrix guard reports that against the enables.
    if self.versions.isEmpty { return }
    let runnable = self.versions.filter(minimum.admits)
    if runnable.isEmpty {
      fatal(
        """
        \(self.enableInput) is set, but the minimum Swift version \(minimum.text) removes every version in \
        \(self.versionAxis.inputName) (\(self.versions.joined(separator: " "))), so it would produce no \
        jobs. \(MinimumVersion.remedy)
        """
      )
    }
    guard let commandsInput = self.commandSource.inputName else { return }
    for variant in self.commands {
      // A label naming no versions of its own runs the group's whole list, which the check
      // above covers.
      guard let versionLabels = variant.versionLabels else { continue }
      guard variant.versions(among: self.versionsExemptFromMinimum + runnable).isEmpty else { continue }
      fatal(
        """
        \(commandsInput) label '\(variant.label)' runs only on \(versionLabels.joined(separator: " ")), which \
        minimum Swift version \(minimum.text) removes, so that label would produce no jobs while the others \
        still run. \(MinimumVersion.remedy)
        """
      )
    }
  }
}

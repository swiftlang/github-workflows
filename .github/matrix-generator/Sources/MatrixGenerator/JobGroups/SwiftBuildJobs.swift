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

/// A group whose entries carry a `swift_build`: the Linux tests, the SDK builds, the Cxx
/// interop check, and Windows. They differ in the axes they fan out over, and in the machines
/// and images those axes name.
struct SwiftBuildJobs: JobGroup {
  var settings: JobGroupSettings
  var platform: MatrixEntry.Platform
  var minimum: MinimumVersion
  var releases: SwiftReleases
  var flags: SwiftFlags
  var setupCommand: String
  var environment: JSONValue
  /// The machines the entries fan out over.
  var runners: [Runner]
  /// The images the entries fan out over, or a single pass with none for entries that run on
  /// the runner itself.
  var images: [ContainerImage?] = [nil]
  /// The SDK the entries build against, which the NDK axis completes.
  var sdk: MatrixEntry.SwiftBuild.SDK?
  /// What only the Android SDK build carries.
  var android: AndroidBuild?

  /// The parts of an Android SDK build that the other SDK builds have no counterpart for.
  struct AndroidBuild {
    /// The triples that are built and nothing more.
    var buildTriples: [String]
    /// The triples that are built and run on an emulator, each in an entry of its own.
    var emulatorTestTriples: [String]
    /// The NDK releases the entries fan out over.
    var ndkVersions: [String]
  }

  /// One entry's value from every axis.
  private struct Combination {
    var runner: Runner
    var image: ContainerImage?
    var ndkVersion: String?
    var variant: Commands.Variant
    var versionLabel: String
  }

  /// One pass per NDK release, or a single pass for a build with no NDK to name.
  private var ndkPasses: [String?] { self.android?.ndkVersions.map(Optional.some) ?? [nil] }

  /// In the order the jobs come out in.
  private var combinations: [Combination] {
    self.runners.flatMap { runner in
      self.images.flatMap { image in
        self.ndkPasses.flatMap { ndkVersion in
          self.settings.commands.flatMap { variant in
            variant.versions(among: self.settings.versions).filter(self.minimum.admits).map {
              Combination(
                runner: runner,
                image: image,
                ndkVersion: ndkVersion,
                variant: variant,
                versionLabel: $0
              )
            }
          }
        }
      }
    }
  }

  /// The triples one entry builds, and whether it runs the emulator on them.
  private struct TripleGroup {
    var triples: [String]
    var runsEmulator: Bool

    /// Names what the entry builds, such as `aarch64-android28+armv7-androideabi28`. The API level
    /// is part of the name because two triples of one architecture can build in separate entries.
    var nameSuffix: String {
      self.triples.map { $0.replacing("-unknown-linux", with: "") }.joined(separator: "+")
    }

    /// The emulator runs what the build produced, so an entry that runs it builds the tests. An
    /// Android build takes none of the flags inputs.
    var buildArguments: [String] {
      self.runsEmulator ? ["--build-tests"] : []
    }
  }

  /// How the Android triples divide across entries, or none for a build with no Android triples.
  /// Each emulator triple gets an entry of its own, and the build-only triples share one that has
  /// no emulator to run, so no emulator waits on builds it never runs.
  private var tripleGroups: [TripleGroup]? {
    guard let android = self.android else {
      return nil
    }
    let emulatorGroups = android.emulatorTestTriples.map { TripleGroup(triples: [$0], runsEmulator: true) }
    if android.buildTriples.isEmpty {
      return emulatorGroups
    }
    return emulatorGroups + [TripleGroup(triples: android.buildTriples, runsEmulator: false)]
  }

  var entries: [MatrixEntry] {
    self.combinations.flatMap { combination -> [MatrixEntry] in
      guard let groups = self.tripleGroups else {
        return [self.entry(for: combination, group: nil, named: false)]
      }
      // Entries are told apart by what they build only when the triples are split across them.
      return groups.map { self.entry(for: combination, group: $0, named: groups.count > 1) }
    }
  }

  private func entry(for combination: Combination, group: TripleGroup?, named: Bool) -> MatrixEntry {
    let toolchain = Toolchain(label: combination.versionLabel, releases: self.releases)
    var sdk = self.sdk
    sdk?.ndkVersion = combination.ndkVersion
    sdk?.triples = group?.triples
    return MatrixEntry(
      platform: self.platform,
      name: self.settings.name(
        "\(self.settings.namePrefix) \(combination.versionLabel)",
        combination.ndkVersion.map { "NDK \($0)" },
        named ? group?.nameSuffix : nil,
        self.images.count > 1 ? combination.image?.distribution : nil,
        self.runners.count > 1 ? combination.runner.name : nil,
        for: combination.variant
      ),
      runner: combination.runner.labels,
      swiftBuild: MatrixEntry.SwiftBuild(
        toolchain,
        sdk: sdk,
        container: combination.image?.container(toolchain)
      ),
      setupCommand: self.setupCommand,
      command: self.command(for: combination),
      commandArguments: group?.buildArguments ?? self.flags.arguments(for: combination.versionLabel),
      env: self.environment,
      androidEmulator: group?.runsEmulator
    )
  }

  /// The command one entry runs. A group whose command is the check itself takes no
  /// per-version replacement.
  private func command(for combination: Combination) -> String {
    switch self.settings.commandSource {
    case .fixed:
      return combination.variant.command
    case .input:
      return self.settings.overrides.command(for: combination.versionLabel) ?? combination.variant.command
    }
  }
}

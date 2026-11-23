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

extension Configuration {
  /// Fails on a pair of inputs that cannot both be honored. Each would otherwise produce a
  /// matrix without the jobs the caller asked for.
  func validatePairings(in mode: Matrix.Mode) {
    // Toolchains mode emits no Android entries, so the triples only matter where they could appear.
    if mode == .jobs && self.androidSDKBuild.enabled {
      if self.androidBuildTriples.isEmpty && self.androidEmulatorTestTriples.isEmpty {
        fatal(
          """
          enable_android_sdk_build is set, but android_sdk_build_triples and android_emulator_test_triples are \
          both empty, so there is nothing to build.
          """
        )
      }

      let triples = self.androidBuildTriples + self.androidEmulatorTestTriples
      if triples.contains(where: { $0.allSatisfy(\.isWhitespace) }) {
        fatal(
          """
          android_sdk_build_triples and android_emulator_test_triples must name each triple, but one is blank; \
          the SDK build is given it as an empty --android-sdk-triple.
          """
        )
      }

      let repeated = Set(triples.filter { triple in triples.filter { $0 == triple }.count > 1 })
      if !repeated.isEmpty {
        fatal(
          """
          \(repeated.sorted().joined(separator: ", ")) appears more than once across \
          android_sdk_build_triples and android_emulator_test_triples; a triple is built once, and either \
          only built or built and tested.
          """
        )
      }
    }
    // An Apple-platform target rides on a macOS entry, so asking for one without enabling
    // macOS produces no jobs at all.
    if !self.xcodeTargets.isEmpty && !self.macOSEnabled {
      fatal("xcode_targets is set but enable_macos is false; xcodebuild targets run on macOS entries.")
    }
    // A Windows container shares the host's kernel, so an image built for another Windows
    // release does not start on it. ltsc2022 is the only Swift Windows image this repository
    // names, so any other label fails rather than being paired with an image that cannot run there.
    if self.windowsEnabled && self.windowsUsesDocker {
      for os in self.windowsOS.names where os != ContainerImage.windowsRunner {
        fatal(
          """
          No Swift Windows container image is known for \(os); windows_use_docker supports \
          windows-2022. Other labels have to run natively.
          """
        )
      }
    }
  }

  /// The images the Linux entries fan out over, or a single pass with none when they run on
  /// the runner itself.
  ///
  /// A distribution the runner does not itself run needs an image: left native, the job would
  /// test the runner's own distribution and pass. It logs the switch, since the caller asked
  /// for a distribution rather than for a container.
  func linuxImages() -> [ContainerImage?] {
    let names = self.linuxOS.names
    if !self.linuxUsesDocker && self.linuxDockerfile.isEmpty {
      if names == [Runner.ubuntuDistribution] { return [nil] }
      if names.count == 1 {
        log("linux_os is \(names[0]) rather than \(Runner.ubuntuDistribution), so Linux runs in a container")
      } else {
        log("linux_os names \(names.count) distributions, so Linux runs in a container")
      }
    }

    return names.map {
      ContainerImage(
        distribution: $0,
        dockerfile: self.linuxDockerfile.isEmpty ? nil : self.linuxDockerfile,
        capabilities: self.linuxCapabilities.isEmpty ? nil : self.linuxCapabilities,
        securityOptions: self.linuxSecurityOptions.isEmpty ? nil : self.linuxSecurityOptions
      )
    }
  }

  /// The Ubuntu runners the Linux entries fan out over, one per architecture.
  var linuxRunners: [Runner] { self.linuxArchitectures.map(Runner.ubuntu(architecture:)) }

  /// The one runner a group that does not fan out over architecture runs on: it follows the
  /// first architecture configured rather than defaulting to one the tests do not use.
  var primaryLinuxRunner: Runner {
    Runner.ubuntu(architecture: self.linuxArchitectures.first ?? "x86_64")
  }

  /// The self-hosted machines the macOS entries run on.
  var macOSMachines: MacOSMachines {
    MacOSMachines(
      operatingSystems: self.macOSOS.names,
      architecture: self.macOSArchitecture,
      pool: self.macOSPool
    )
  }

  /// What the relative and alias labels resolve to.
  var releases: SwiftReleases {
    SwiftReleases(
      currentRelease: self.currentRelease.isEmpty ? nil : self.currentRelease,
      nightlyBranch: self.nightlyBranch.isEmpty ? nil : self.nightlyBranch
    )
  }

  /// The Swift versions the macOS entries run.
  ///
  /// The two macOS lists are different ways of naming a toolchain, not competing spellings
  /// of one, so they combine; the release list is the default only when neither is set.
  var macOSSwiftVersions: [String] {
    if self.macOSVersions.isEmpty && self.macOSXcodeVersions.isEmpty {
      return Configuration.releaseLabels
    }
    return self.macOSVersions
  }

  /// The Swift versions the Cxx interop check runs: those the Linux tests run, unless a caller
  /// names others.
  var cxxInteropSwiftVersions: [String] {
    self.cxxInteropVersions.isEmpty ? self.linuxVersions : self.cxxInteropVersions
  }

  /// The timeout an entry on this platform carries, or nil to leave the executor's own.
  func timeoutMinutes(for platform: MatrixEntry.Platform) -> Int? {
    let minutes: Int
    switch platform {
    case .windows: minutes = self.windowsTimeoutMinutes
    case .freeBSD: minutes = self.freeBSDTimeoutMinutes
    case .linux, .macOS: minutes = 0
    }

    return minutes > 0 ? minutes : nil
  }

  /// The shell a setup command runs under, which decides how a path is written.
  enum PackageShell {
    /// bash, on Linux, macOS and FreeBSD.
    case posix
    /// PowerShell, for a Windows job on the runner.
    case powershell
    /// cmd, for a Windows container, which receives its commands as one command line.
    case cmd
  }

  /// The setup command with a `cd` into the package appended. The setup command and the command
  /// run in one shell on every platform, so the caller's own setup runs from the repository
  /// root, where its relative paths are written, and the command runs in the package.
  func enteringPackage(after setupCommand: String, under shell: PackageShell = .posix) -> String {
    if self.packagePath.isEmpty || self.packagePath == "." { return setupCommand }
    let forbidden = CharacterSet(charactersIn: "\"$`\\\n\r")
    if self.packagePath.rangeOfCharacter(from: forbidden) != nil {
      fatal(
        """
        package_path must be a plain directory, without quotes, $, backticks or backslashes, \
        but got: \(self.packagePath)
        """
      )
    }

    let enter: String
    switch shell {
    case .posix:
      enter = "cd \"\(self.packagePath)\""

    case .powershell:
      enter = "cd \"\(self.packagePath.replacingOccurrences(of: "/", with: "\\"))\""

    case .cmd:
      // A double quote inside the command line reaches cmd as a literal `\"`, so the path is
      // written bare, and cmd rejects a forward slash in a `cd` it is given that way.
      if self.packagePath.rangeOfCharacter(from: .whitespaces) != nil {
        fatal("package_path cannot contain whitespace for a Windows container, but got: \(self.packagePath)")
      }
      enter = "cd \(self.packagePath.replacingOccurrences(of: "/", with: "\\"))"
    }
    return setupCommand.isEmpty ? enter : "\(setupCommand.trimmingTrailingNewlines)\n\(enter)"
  }

  /// The flags an entry's command runs with, and what a version's override adds to them.
  func flags(with overrides: VersionOverrides = VersionOverrides()) -> SwiftFlags {
    SwiftFlags(release: self.swiftFlags, nightly: self.swiftNightlyFlags, overrides: overrides)
  }
}

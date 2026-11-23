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

struct Generator {
  private let configuration: Configuration
  private let mode: Matrix.Mode

  /// Derived once when the run starts rather than at each point one is read: deriving one
  /// logs what it resolved to, and reading it twice would log it twice.
  private let linuxImages: [ContainerImage?]
  private let minimum: MinimumVersion
  /// Derived once for the same reason.
  private let xcodeTargets: [XcodeTarget]

  /// Everything else a group needs is read from the configuration as that group is built.
  init(_ configuration: Configuration, mode: Matrix.Mode) {
    self.configuration = configuration
    self.mode = mode
    self.linuxImages = configuration.linuxImages()
    self.minimum = MinimumVersion(for: configuration)
    self.xcodeTargets = XcodeTarget.list(in: configuration)
  }
}

extension Generator {
  private var linuxJobs: SwiftBuildJobs {
    SwiftBuildJobs(
      settings: JobGroupSettings(
        enableInput: "enable_linux",
        versionAxis: .list(input: "linux_swift_versions"),
        versions: self.configuration.linuxVersions,
        commandSource: .input(name: "linux_command"),
        commands: self.configuration.linuxCommands,
        overrides: self.configuration.linuxOverrides,
        namePrefix: "Linux Swift"
      ),
      platform: .linux,
      minimum: self.minimum,
      releases: self.configuration.releases,
      flags: self.configuration.flags(with: self.configuration.linuxOverrides),
      setupCommand: self.configuration.enteringPackage(after: self.configuration.linuxSetupCommand),
      environment: self.configuration.linuxEnvironment,
      runners: self.configuration.linuxRunners,
      images: self.linuxImages
    )
  }

  private var macOSJobs: MacOSJobs {
    MacOSJobs(
      settings: JobGroupSettings(
        enableInput: "enable_macos",
        versionAxis: .list(input: "macos_swift_versions"),
        versions: self.configuration.macOSSwiftVersions,
        commandSource: .input(name: "macos_command"),
        commands: self.configuration.macOSCommands,
        overrides: self.configuration.macOSOverrides,
        versionsExemptFromMinimum: self.configuration.macOSXcodeVersions,
        namePrefix: "macOS Swift"
      ),
      minimum: self.minimum,
      releases: self.configuration.releases,
      flags: self.configuration.flags(with: self.configuration.macOSOverrides),
      setupCommand: self.configuration.enteringPackage(after: self.configuration.macOSSetupCommand),
      environment: self.configuration.macOSEnvironment,
      machines: self.configuration.macOSMachines,
      targets: self.xcodeTargets,
      debugOutput: self.configuration.xcodeDebugOutput
    )
  }

  private var macOSSwiftlyJobs: MacOSSwiftlyJobs {
    MacOSSwiftlyJobs(
      settings: JobGroupSettings(
        enableInput: "enable_macos_swiftly",
        versionAxis: .toolchains(input: "macos_swiftly_toolchains"),
        versions: [],
        commandSource: .input(name: "macos_swiftly_command"),
        commands: self.configuration.swiftlyCommands,
        namePrefix: "macOS Swiftly"
      ),
      flags: self.configuration.flags(),
      setupCommand: self.configuration.enteringPackage(after: self.configuration.macOSSetupCommand),
      environment: self.configuration.macOSEnvironment,
      machines: self.configuration.macOSMachines,
      toolchains: self.configuration.swiftlyToolchains
    )
  }

  private var windowsJobs: SwiftBuildJobs {
    SwiftBuildJobs(
      settings: JobGroupSettings(
        enableInput: "enable_windows",
        versionAxis: .list(input: "windows_swift_versions"),
        versions: self.configuration.windowsVersions,
        commandSource: .input(name: "windows_command"),
        commands: self.configuration.windowsCommands,
        overrides: self.configuration.windowsOverrides,
        namePrefix: "Windows Swift"
      ),
      platform: .windows,
      minimum: self.minimum,
      releases: self.configuration.releases,
      flags: self.configuration.flags(with: self.configuration.windowsOverrides),
      setupCommand: self.configuration.enteringPackage(
        after: self.configuration.windowsSetupCommand,
        under: self.configuration.windowsUsesDocker ? .cmd : .powershell
      ),
      environment: self.configuration.windowsEnvironment,
      runners: self.configuration.windowsOS.names.map(Runner.windows(label:)),
      images: self.configuration.windowsUsesDocker ? [.windows] : [nil]
    )
  }

  private var cxxInteropJobs: SwiftBuildJobs {
    SwiftBuildJobs(
      settings: JobGroupSettings(
        enableInput: "enable_cxx_interop",
        versionAxis: .list(input: "cxx_interop_swift_versions"),
        versions: self.configuration.cxxInteropSwiftVersions,
        // The check is the command rather than a place to run one, so it takes none as input.
        // The runner expands SCRIPTS_ROOT, so that reference stays literal here.
        commandSource: .fixed,
        commands: "${SCRIPTS_ROOT}/check-cxx-interop.sh",
        namePrefix: "Cxx interop Swift"
      ),
      platform: .linux,
      minimum: self.minimum,
      releases: self.configuration.releases,
      flags: self.configuration.flags(),
      setupCommand: self.configuration.enteringPackage(after: self.configuration.linuxSetupCommand),
      environment: self.configuration.linuxEnvironment,
      runners: [self.configuration.primaryLinuxRunner],
      images: self.linuxImages
    )
  }

  private var freeBSDJobs: FreeBSDJobs {
    FreeBSDJobs(
      settings: JobGroupSettings(
        enableInput: "enable_freebsd",
        versionAxis: .list(input: "freebsd_swift_versions"),
        versions: self.configuration.freeBSDVersions,
        commandSource: .input(name: "freebsd_command"),
        commands: self.configuration.freeBSDCommands,
        namePrefix: "FreeBSD"
      ),
      setupCommand: self.configuration.enteringPackage(after: self.configuration.freeBSDSetupCommand),
      osVersions: self.configuration.freeBSDOSVersions,
      buildFlags: self.configuration.swiftNightlyFlags,
      environmentVariables: self.configuration.freeBSDEnvironmentVariables
    )
  }

  /// A group that builds against a Swift SDK. Its inputs all share one prefix, and it fans out
  /// over neither the distribution nor the architecture: install-and-build-with-sdk.sh
  /// fetches a toolchain matched to the SDK, and job-runner-linux.sh refuses an entry
  /// carrying both an sdk and a container.
  private func sdkJobs(_ build: SDKBuild) -> SwiftBuildJobs {
    let overrides = build.overrides
    var jobs = SwiftBuildJobs(
      settings: JobGroupSettings(
        enableInput: build.enableInput,
        versionAxis: .list(input: build.versionsInput),
        versions: build.versions,
        commandSource: .input(name: build.commandInput),
        commands: build.commands,
        overrides: overrides,
        namePrefix: build.name
      ),
      platform: .linux,
      minimum: self.minimum,
      releases: self.configuration.releases,
      flags: self.configuration.flags(with: overrides),
      setupCommand: self.configuration.enteringPackage(after: build.setupCommand),
      environment: self.configuration.linuxEnvironment,
      runners: [self.configuration.primaryLinuxRunner],
      sdk: MatrixEntry.SwiftBuild.SDK(kind: build.kind)
    )

    guard build.kind == .android else { return jobs }
    jobs.android = SwiftBuildJobs.AndroidBuild(
      buildTriples: self.configuration.androidBuildTriples,
      emulatorTestTriples: self.configuration.androidEmulatorTestTriples,
      ndkVersions: self.configuration.androidNDKVersions
    )
    return jobs
  }

  /// The groups this run produces entries for, in the order the jobs come out in.
  ///
  /// A group nobody asked for is not built, so nothing it carries is read and nothing it
  /// carries can fail the run. This is the only place that decides whether a group is built.
  private var jobGroups: [any JobGroup] {
    var groups: [any JobGroup] = []
    if self.configuration.linuxEnabled { groups.append(self.linuxJobs) }
    if self.configuration.macOSEnabled { groups.append(self.macOSJobs) }
    if self.configuration.swiftlyEnabled { groups.append(self.macOSSwiftlyJobs) }
    if self.configuration.windowsEnabled { groups.append(self.windowsJobs) }
    // A group that exists only to run a particular command has no meaning where the caller
    // supplies the command instead, so toolchains mode does not emit those.
    if self.mode == .toolchains { return groups }
    groups += self.configuration.sdkBuilds.filter(\.enabled).map(self.sdkJobs)
    if self.configuration.cxxInteropEnabled { groups.append(self.cxxInteropJobs) }
    if self.configuration.freeBSDEnabled { groups.append(self.freeBSDJobs) }
    return groups
  }
}

extension Generator {
  func generate() -> Matrix {
    let groups = self.jobGroups

    // An overrides key is valid if it names a version in any enabled group that reads it: the
    // lists are independent, so an SDK build can name a version the Linux test list does not.
    var readable: [String: [String]] = [:]
    for group in groups {
      readable[group.settings.overrides.name, default: []] += group.settings.selectableVersions
    }
    for overrides in self.configuration.allOverrides {
      overrides.validateKeys(against: Set(readable[overrides.name] ?? []).sorted())
    }

    for group in groups { group.validate(against: self.minimum) }

    // A group the caller asked for that produces nothing is a job missing from a run that
    // still reports success, whatever the other groups produced. A deliberate skip - toolchains
    // mode - leaves the group unbuilt, so it is not such a group.
    var entries: [MatrixEntry] = []
    for group in groups {
      let produced = group.entries
      if produced.isEmpty {
        fatal(
          """
          \(group.settings.enableInput) is set, but produces no jobs: one of the lists it fans out over \
          is empty, so the run would report success without them.
          """
        )
      }
      entries += produced.map { entry in
        var timed = entry
        timed.timeoutMinutes = self.configuration.timeoutMinutes(for: entry.platform)
        return timed
      }
    }

    if groups.isEmpty {
      log("No matrix entries: nothing is enabled")
    } else {
      log("Generated \(entries.count) matrix entries")
    }

    switch self.mode {
    case .jobs: return Matrix(config: entries)
    case .toolchains: return Matrix(config: entries.map(\.withoutCommands))
    }
  }
}

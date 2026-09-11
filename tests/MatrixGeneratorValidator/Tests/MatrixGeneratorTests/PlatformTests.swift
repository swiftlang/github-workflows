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

import MatrixTestSupport
import Testing

@Suite("macOS")
struct MacOSTests {
  @Test("A macOS entry names either a Swift version or an Xcode version, not both")
  func selector() throws {
    let bySwift = try Generator.run(["ENABLE_MACOS": "true", "MACOS_SWIFT_VERSIONS": #"["6.3"]"#])
    let swiftBuild = try #require(bySwift.entries.first?.xcodeBuild)
    #expect(swiftBuild.swiftVersion == "6.3")
    #expect(swiftBuild.xcodeVersion == nil)

    let byXcode = try Generator.run(["ENABLE_MACOS": "true", "MACOS_XCODE_VERSIONS": #"["26.3"]"#])
    let xcodeBuild = try #require(byXcode.entries.first?.xcodeBuild)
    #expect(xcodeBuild.xcodeVersion == "26.3")
    #expect(xcodeBuild.swiftVersion == nil)
  }

  @Test("The two macOS version lists combine rather than one replacing the other")
  func versionListsCombine() throws {
    // They are different ways of naming a toolchain, not competing spellings of
    // one. NIO's macOS configuration wants a pinned Xcode beta alongside the
    // release versions, which needs an entry from each list.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.2","6.3"]"#,
      "MACOS_XCODE_VERSIONS": #"["latest-beta"]"#,
    ])
    #expect(generated.names == ["macOS Xcode latest-beta", "macOS Swift 6.2", "macOS Swift 6.3"])
  }

  @Test("An override key is valid if it names a version in either macOS list")
  func overrideKeysValidatedAgainstBothLists() throws {
    // The lists combine, so validating against each on its own would reject a key
    // naming a version from the other. A caller setting both lists and overriding
    // only the Xcode entry hits exactly that.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "MACOS_XCODE_VERSIONS": #"["latest-beta"]"#,
      "MACOS_VERSION_OVERRIDES": #"{"latest-beta": "-Xswiftc -DBETA"}"#,
    ])
    #expect(generated.exitCode == 0)
    #expect(
      generated.entry(named: "macOS Xcode latest-beta")?.commandArguments
        == ["-Xswiftc", "-DBETA"]
    )
    #expect(generated.entry(named: "macOS Swift 6.3")?.commandArguments == [])

    // A key naming neither list is still rejected.
    let bogus = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "MACOS_XCODE_VERSIONS": #"["latest-beta"]"#,
      "MACOS_VERSION_OVERRIDES": #"{"6.9": "-Xswiftc -DNOPE"}"#,
    ])
    #expect(bogus.exitCode != 0)
  }

  @Test("The minimum Swift version filters macOS as it does every other platform")
  func minimumVersionAppliesToMacOS() throws {
    // A toolchain below the manifest's tools version cannot resolve the package,
    // so a macOS job on it fails for a reason the caller did not ask about.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "ENABLE_MACOS": "true",
      "MINIMUM_SWIFT_VERSION": "6.2",
      "LINUX_SWIFT_VERSIONS": #"["6.0","6.1","6.2"]"#,
      "MACOS_SWIFT_VERSIONS": #"["6.0","6.1","6.2"]"#,
    ])
    #expect(generated.names == ["Linux Swift 6.2", "macOS Swift 6.2"])
  }

  @Test("Runner labels come from the OS, architecture and pool")
  func runnerLabels() throws {
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "MACOS_OS": "sequoia",
      "MACOS_ARCH": "X64",
      "MACOS_RUNNER_POOL": "nightly",
    ])
    #expect(generated.entries.first?.runner == ["self-hosted", "macos", "sequoia", "X64", "nightly"])
  }

  @Test("A map names the platforms and what each one does")
  func targetsFromMap() throws {
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_SCHEME": "P-Package",
      "XCODE_TARGETS": """
        iOS: {build: true, test: true}
        watchOS: {build: true}
        """,
    ])
    let targets = try #require(generated.entries.first?.xcodeBuild?.targets)
    try #require(targets.count == 2)
    #expect(targets.map(\.platform) == ["iOS", "watchOS"])
    #expect(targets[0].build == true)
    #expect(targets[0].test == true)
    #expect(targets[1].build == true)
    #expect(targets[1].test == false, "testing needs a simulator, so it is asked for rather than assumed")
    #expect(targets[0].scheme == "P-Package")
  }

  @Test("macOS and Mac Catalyst are available as destinations")
  func macOSAndCatalystTargets() throws {
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_SCHEME": "P-Package",
      "XCODE_TARGETS": "{macOS: {}, Catalyst: {}}",
    ])
    let targets = try #require(generated.entries.first?.xcodeBuild?.targets)
    try #require(targets.count == 2)
    #expect(targets.map(\.platform) == ["macOS", "Catalyst"])
    #expect(targets[1].buildDestination == "generic/platform=macos,variant=Mac Catalyst")
  }

  @Test("A target without a scheme fails rather than building nothing")
  func targetsNeedAScheme() throws {
    // xcodebuild has nothing to build without a scheme, so the entry would carry
    // an empty target list and the job would pass having checked nothing. This is
    // the first thing a caller migrating off enable_ios_checks hits.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_TARGETS": "[iOS]",
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("xcode_scheme"))
  }

  @Test("An Apple-platform target without macOS fails rather than generating nothing")
  func targetsNeedMacOS() throws {
    // The targets ride on a macOS entry, so without one there is nothing for them
    // to attach to and the matrix comes out empty.
    let generated = try Generator.run([
      "XCODE_SCHEME": "P-Package",
      "XCODE_TARGETS": "[iOS]",
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("enable_macos"))
  }

  @Test("The debug-output flag reaches the entry")
  func debugOutput() throws {
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_DEBUG_OUTPUT": "true",
    ])
    #expect(generated.entries.first?.xcodeBuild?.debugOutput == true)
  }

  @Test("A swiftly toolchain pairs a selector with an Xcode, and may override the runner")
  func swiftlyToolchains() throws {
    let generated = try Generator.run([
      "ENABLE_MACOS_SWIFTLY": "true",
      "MACOS_SWIFTLY_TOOLCHAINS":
        #"[{"xcode_version":"swift_6.3","swiftly_toolchain":"main-snapshot","os_version":"sequoia","arch":"X64"}]"#,
      "MACOS_SWIFTLY_COMMAND": "swiftly run swift build",
    ])
    let entry = try #require(generated.entries.first)
    #expect(entry.xcodeBuild?.xcodeVersion == "swift_6.3")
    #expect(entry.xcodeBuild?.swiftlyToolchain == "main-snapshot")
    #expect(entry.runner == ["self-hosted", "macos", "sequoia", "X64", "general"])
    #expect(entry.command == "swiftly run swift build")
  }

  @Test("A snapshot selector takes the nightly flags")
  func swiftlySnapshotTakesNightlyFlags() throws {
    let generated = try Generator.run([
      "ENABLE_MACOS_SWIFTLY": "true",
      "SWIFT_FLAGS": "-Xswiftc -DRELEASE",
      "SWIFT_NIGHTLY_FLAGS": "-Xswiftc -DNIGHTLY",
    ])
    #expect(generated.entries.first?.commandArguments == ["-Xswiftc", "-DNIGHTLY"])
  }

  @Test("A swiftly entry missing its Xcode version or its selector fails")
  func incompleteSwiftlyEntry() throws {
    // Skipping the entry drops a job from a run that still reports success, so a
    // caller who misspells one of the two keys never learns the entry did nothing.
    let onlyBadEntry = try Generator.run([
      "ENABLE_MACOS_SWIFTLY": "true",
      "MACOS_SWIFTLY_TOOLCHAINS": #"[{"swiftly_toolchain":"main-snapshot"}]"#,
    ])
    #expect(onlyBadEntry.exitCode != 0)
    #expect(onlyBadEntry.count == 0)
    #expect(onlyBadEntry.standardError.contains("xcode_version"))

    // A good entry alongside is the case that has to fail: the matrix is no longer
    // empty, so the empty-matrix guard cannot catch it.
    let alongsideAGoodEntry = try Generator.run([
      "ENABLE_MACOS_SWIFTLY": "true",
      "MACOS_SWIFTLY_TOOLCHAINS": """
        [{"swiftly_toolchain":"main-snapshot"},\
        {"xcode_version":"swift_6.3","swiftly_toolchain":"main-snapshot"}]
        """,
    ])
    #expect(alongsideAGoodEntry.exitCode != 0)
    #expect(alongsideAGoodEntry.standardError.contains("xcode_version"))
  }

  @Test("A swiftly entry's runner follows macos_os")
  func swiftlyRunnerFollowsOSList() throws {
    // The pools are self-hosted, so an entry naming an OS the caller did not ask
    // for queues until it times out - the failure macos_repository_owner exists to
    // prevent.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "ENABLE_MACOS_SWIFTLY": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "MACOS_OS": #"["sequoia"]"#,
    ])
    #expect(generated.count == 2)
    for entry in generated.entries {
      #expect(entry.runner.contains("sequoia"), "\(entry.name) ignored macos_os")
      #expect(!entry.runner.contains("tahoe"), "\(entry.name) used the default OS")
    }

    // An entry naming its own OS still wins over the list.
    let named = try Generator.run([
      "ENABLE_MACOS_SWIFTLY": "true",
      "MACOS_OS": #"["sequoia"]"#,
      "MACOS_SWIFTLY_TOOLCHAINS": """
        [{"xcode_version":"swift_6.3","swiftly_toolchain":"main-snapshot","os_version":"sonoma"}]
        """,
    ])
    #expect(named.entries.first?.runner.contains("sonoma") == true)
  }

  @Test("Swiftly entries fan out over the macOS OS list")
  func swiftlyFansOutOverOSList() throws {
    // Each macOS OS is a pool of its own, so a swiftly entry taking only the first
    // leaves the rest of the list with no swiftly coverage at all.
    let generated = try Generator.run([
      "ENABLE_MACOS_SWIFTLY": "true",
      "MACOS_OS": #"["sequoia","tahoe"]"#,
      "MACOS_SWIFTLY_TOOLCHAINS":
        #"[{"xcode_version":"swift_6.3","swiftly_toolchain":"main-snapshot"}]"#,
    ])
    try #require(generated.count == 2)
    #expect(
      generated.names == [
        "macOS Swiftly main-snapshot (Xcode swift_6.3) sequoia",
        "macOS Swiftly main-snapshot (Xcode swift_6.3) tahoe",
      ]
    )
    #expect(generated.entries[0].runner.contains("sequoia"))
    #expect(generated.entries[1].runner.contains("tahoe"))

    // An entry naming its own OS runs there alone. Fanning it out as well would
    // give one entry per configured OS, all on the pinned one and all named alike.
    let pinned = try Generator.run([
      "ENABLE_MACOS_SWIFTLY": "true",
      "MACOS_OS": #"["sequoia","tahoe"]"#,
      "MACOS_SWIFTLY_TOOLCHAINS": """
        [{"xcode_version":"swift_6.3","swiftly_toolchain":"main-snapshot","os_version":"sonoma"},\
        {"xcode_version":"swift_6.2","swiftly_toolchain":"6.2-snapshot"}]
        """,
    ])
    try #require(pinned.count == 3)
    #expect(
      pinned.names == [
        "macOS Swiftly main-snapshot (Xcode swift_6.3) sonoma",
        "macOS Swiftly 6.2-snapshot (Xcode swift_6.2) sequoia",
        "macOS Swiftly 6.2-snapshot (Xcode swift_6.2) tahoe",
      ]
    )
  }

  @Test("One macOS OS leaves the swiftly job name alone, however it is written")
  func oneOSLeavesTheSwiftlyNameAlone() throws {
    // Entry names are required status checks in adopting repositories, so a name
    // gains the OS only when more than one is configured.
    func names(_ macOSOS: String?) throws -> [String] {
      var environment = [
        "ENABLE_MACOS_SWIFTLY": "true",
        "MACOS_SWIFTLY_TOOLCHAINS":
          #"[{"xcode_version":"swift_6.3","swiftly_toolchain":"main-snapshot"}]"#,
      ]
      if let macOSOS {
        environment["MACOS_OS"] = macOSOS
      }
      return try Generator.run(environment).names
    }

    let bare = ["macOS Swiftly main-snapshot (Xcode swift_6.3)"]
    #expect(try names(nil) == bare)
    #expect(try names("sequoia") == bare)
    #expect(try names(#"["sequoia"]"#) == bare)
    // Without this the names above would be stable because nothing fans out.
    #expect(try names(#"["sequoia","tahoe"]"#).count == 2)
  }

  @Test("Self-hosted entries are withheld from other owners")
  func ownerGuard() throws {
    let matching = try Generator.run([
      "ENABLE_MACOS": "true",
      "ENABLE_MACOS_SWIFTLY": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "MACOS_REPOSITORY_OWNER": "apple",
      "GITHUB_REPOSITORY_OWNER": "apple",
    ])
    #expect(matching.count == 2)

    let fork = try Generator.run([
      "ENABLE_MACOS": "true",
      "ENABLE_MACOS_SWIFTLY": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "MACOS_REPOSITORY_OWNER": "apple",
      "GITHUB_REPOSITORY_OWNER": "a-fork",
    ])
    #expect(fork.count == 0, "a fork cannot reach the pools, so it should get no jobs at all")

    let unguarded = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "GITHUB_REPOSITORY_OWNER": "a-fork",
    ])
    #expect(unguarded.count == 1)
  }
}

@Suite("Apple platform targets")
struct ApplePlatformTargetTests {
  /// Every platform NIO builds and tests, and the destinations each uses.
  @Test(
    "Each platform has a build and a test destination",
    arguments: [
      ("macOS", "generic/platform=macos,variant=macos", "name=My Mac,variant=macos"),
      (
        "Catalyst", "generic/platform=macos,variant=Mac Catalyst",
        "name=My Mac,variant=Mac Catalyst"
      ),
      ("iOS", "generic/platform=ios", "name=iPhone Air"),
      ("watchOS", "generic/platform=watchos", "name=Apple Watch Ultra 3 (49mm)"),
      ("tvOS", "generic/platform=tvos", "name=Apple TV 4K (3rd generation)"),
      ("visionOS", "generic/platform=visionos", "name=Apple Vision Pro"),
    ]
  )
  func destinations(
    platform: String,
    buildDestination: String,
    testDestination: String
  ) throws {
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_SCHEME": "P-Package",
      "XCODE_TARGETS": "\(platform): {build: true, test: true}",
    ])
    let targets = try #require(generated.entries.first?.xcodeBuild?.targets)
    try #require(targets.count == 1)
    #expect(targets.map(\.platform) == [platform])
    #expect(targets[0].buildDestination == buildDestination)
    #expect(targets[0].testDestination == testDestination)
    #expect(targets[0].build == true)
    #expect(targets[0].test == true)
  }

  @Test("A bare list asks for each platform with every setting at its default")
  func bareListTakesTheDefaults() throws {
    // The common case is a build on several platforms with nothing else said, and
    // writing an empty settings map for each of them is noise.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_SCHEME": "P-Package",
      "XCODE_TARGETS": "[iOS, watchOS]",
    ])
    let targets = try #require(generated.entries.first?.xcodeBuild?.targets)
    try #require(targets.count == 2)
    #expect(targets.map(\.platform) == ["iOS", "watchOS"])
    for target in targets {
      #expect(target.build == true)
      #expect(target.test == false)
      #expect(target.scheme == "P-Package")
      #expect(!target.buildDestination.isEmpty)
      #expect(!target.testDestination.isEmpty)
    }
  }

  @Test("Testing on a platform is asked for on top of building, and building can be dropped")
  func buildAndTestAreIndependent() throws {
    // The build action is build-for-testing, so a build alone still type-checks
    // the tests - which is what the retired enable_ios_checks did, without a
    // runner of its own. Running them is the expensive part, so it is opt-in.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_SCHEME": "P-Package",
      "XCODE_TARGETS": """
        iOS: {test: true}
        tvOS: {build: false, test: true}
        """,
    ])
    let targets = try #require(generated.entries.first?.xcodeBuild?.targets)
    try #require(targets.count == 2)
    #expect(targets[0].build == true)
    #expect(targets[0].test == true)
    #expect(targets[1].build == false)
    #expect(targets[1].test == true)
  }

  @Test("A target's scheme overrides xcode_scheme, which the rest keep")
  func perTargetScheme() throws {
    // A package can expose more than one scheme, and a platform is often covered
    // by a scheme of its own.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_SCHEME": "P-Package",
      "XCODE_TARGETS": """
        iOS: {scheme: iOS-Only}
        tvOS: {}
        """,
    ])
    let targets = try #require(generated.entries.first?.xcodeBuild?.targets)
    try #require(targets.count == 2)
    #expect(targets[0].scheme == "iOS-Only")
    #expect(targets[1].scheme == "P-Package")
  }

  @Test("A target's destinations override the defaults")
  func perTargetDestinations() throws {
    // The default destinations name the newest device of each kind, which ages
    // with every Xcode release. An adopter pinned to an older Xcode, or one
    // testing a device the default does not name, would otherwise be stuck.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_SCHEME": "P-Package",
      "XCODE_TARGETS": """
        iOS: {test: true, test_destination: "name=iPhone 16 Pro"}
        watchOS: {build_destination: "generic/platform=watchOS Simulator"}
        """,
    ])
    let targets = try #require(generated.entries.first?.xcodeBuild?.targets)
    try #require(targets.count == 2)
    #expect(targets[0].testDestination == "name=iPhone 16 Pro")
    #expect(targets[0].buildDestination == "generic/platform=ios", "the build destination is untouched")
    #expect(targets[1].buildDestination == "generic/platform=watchOS Simulator")
    #expect(
      targets[1].testDestination == "name=Apple Watch Ultra 3 (49mm)",
      "the test destination is untouched"
    )
  }

  @Test(
    "A target the caller got wrong fails, naming the input",
    arguments: [
      "[iOS",
      "iOS",
      "[ios]",
      "iOS: true",
      "iOS: {sheme: P-Package}",
      "iOS: {build: false, test: false}",
    ]
  )
  func malformedTargetsFail(targets: String) throws {
    // Each of these would otherwise leave a platform out of a run that reports
    // success: a misspelled platform or setting is dropped, and a target that
    // neither builds nor tests does nothing.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_SCHEME": "P-Package",
      "XCODE_TARGETS": targets,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.count == 0)
    #expect(generated.standardError.contains("xcode_targets"))
  }

  @Test("A bad target alongside a good one still fails")
  func oneBadTargetFailsTheRun() throws {
    // The good target fills the array, so a check on the array being empty would
    // not catch this.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_SCHEME": "P-Package",
      "XCODE_TARGETS": """
        iOS: {build: true}
        iPadOS: {build: true}
        """,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.count == 0)
    #expect(generated.standardError.contains("iPadOS"))
  }

  @Test("Configuring targets leaves the job names alone")
  func targetsDoNotRenameJobs() throws {
    // Entry names become required status checks in adopting repositories, and two
    // swift-nio dev/ scripts parse them out of `gh pr checks`. The targets run as
    // steps inside a macOS job, so no configuration of them may move a name.
    func generate(_ targets: String?) throws -> Generated {
      var environment = [
        "ENABLE_LINUX": "true",
        "ENABLE_MACOS": "true",
        "ENABLE_WINDOWS": "true",
        "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
        "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
        "MACOS_XCODE_VERSIONS": #"["latest-beta"]"#,
        "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#,
        "XCODE_SCHEME": "P-Package",
      ]
      if let targets {
        environment["XCODE_TARGETS"] = targets
      }
      return try Generator.run(environment)
    }

    let expected = [
      "Linux Swift 6.3", "macOS Xcode latest-beta", "macOS Swift 6.3", "Windows Swift 6.3",
    ]
    #expect(try generate(nil).names == expected)

    let everyPlatform = try generate("[macOS, Catalyst, iOS, watchOS, tvOS, visionOS]")
    #expect(everyPlatform.names == expected)
    // Without this the names above would be stable because nothing was configured.
    #expect(everyPlatform.entry(named: "macOS Swift 6.3")?.xcodeBuild?.targets?.count == 6)

    let oneOverriddenTarget = try generate(
      #"iOS: {test: true, scheme: Other-Package, test_destination: "name=iPhone 16"}"#
    )
    #expect(oneOverriddenTarget.names == expected)
    #expect(oneOverriddenTarget.entry(named: "macOS Swift 6.3")?.xcodeBuild?.targets?.count == 1)
  }

  @Test("Apple platform targets ride on the macOS entries rather than their own")
  func noExtraRunners() throws {
    // NIO's reason for this shape: a separate runner per platform is expensive,
    // because macOS runner recycling is slow.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "XCODE_SCHEME": "P-Package",
      "XCODE_TARGETS": "[iOS, watchOS, tvOS, visionOS]",
    ])
    #expect(generated.count == 1)
    #expect(generated.entries.first?.xcodeBuild?.targets?.count == 4)
  }
}

@Suite("Windows")
struct WindowsTests {
  @Test("Windows is native until a container is asked for")
  func nativeUntilContainerRequested() throws {
    // A Swift release before 6.1 cannot build ucrt against the runner image's
    // Windows SDK, so an adopter of one needs a container and has to ask for it.
    let byDefault = try Generator.run([
      "ENABLE_WINDOWS": "true", "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#,
    ])
    #expect(byDefault.entries.first?.swiftBuild?.container == nil)

    let containerized = try Generator.run([
      "ENABLE_WINDOWS": "true",
      "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#,
      "WINDOWS_USE_DOCKER": "true",
    ])
    #expect(
      containerized.entries.first?.swiftBuild?.container?.image
        == "swift:6.3-windowsservercore-ltsc2022"
    )
  }

  @Test("The runner comes from the OS list, which also names the job")
  func runnersFromOSList() throws {
    let generated = try Generator.run([
      "ENABLE_WINDOWS": "true",
      "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#,
      "WINDOWS_OS": #"["windows-2022","windows-11-arm"]"#,
    ])
    #expect(generated.entries.map { $0.runner.first } == ["windows-2022", "windows-11-arm"])
    #expect(generated.names == ["Windows Swift 6.3 windows-2022", "Windows Swift 6.3 windows-11-arm"])
  }

  @Test("Container images use the Windows tag")
  func containerImage() throws {
    let generated = try Generator.run([
      "ENABLE_WINDOWS": "true",
      "WINDOWS_SWIFT_VERSIONS": #"["nightly-release"]"#,
      "WINDOWS_USE_DOCKER": "true",
    ])
    #expect(
      generated.entries.first?.swiftBuild?.container?.image
        == "swiftlang/swift:nightly-6.4.x-windowsservercore-ltsc2022"
    )
  }

  @Test(
    "A runner label with no known image fails rather than pairing one it cannot run",
    arguments: ["windows-2025", "windows-11-arm", "windows-latest"]
  )
  func containerTagFollowsTheRunnerLabel(label: String) throws {
    // The label names the host, and a Windows container shares the host's kernel:
    // an image built for another Windows release does not start there, so a job
    // pinned to a tag the label does not match fails inside `docker run` with
    // nothing pointing back at windows_os.
    let containerized = try Generator.run([
      "ENABLE_WINDOWS": "true",
      "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#,
      "WINDOWS_OS": label,
      "WINDOWS_USE_DOCKER": "true",
    ])
    #expect(containerized.exitCode != 0)
    #expect(containerized.count == 0)
    #expect(containerized.standardError.contains(label))

    // The same label runs natively, which is the mode these runners support.
    let native = try Generator.run([
      "ENABLE_WINDOWS": "true",
      "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#,
      "WINDOWS_OS": label,
    ])
    #expect(native.exitCode == 0)
    #expect(native.entries.first?.runner == [label])
  }

  @Test("One label with no image fails the run, not just its own entries")
  func oneUnknownLabelFailsTheRun() throws {
    // windows-2022 fills the matrix, so a check on the matrix being empty would not
    // catch this, and the run would come back green having skipped an OS.
    let generated = try Generator.run([
      "ENABLE_WINDOWS": "true",
      "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#,
      "WINDOWS_OS": #"["windows-2022","windows-2025"]"#,
      "WINDOWS_USE_DOCKER": "true",
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.count == 0)
    #expect(generated.standardError.contains("windows-2025"))
  }
}

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

// There is one test per axis of customization, asserting only what that axis
// controls, so a failure names the feature that broke rather than showing a whole
// matrix and leaving the reader to work out which part matters.

@Suite("Platform selection")
struct PlatformSelectionTests {
  @Test(
    "Each enable flag selects its platform",
    arguments: [
      (["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#], "Linux"),
      (["ENABLE_WINDOWS": "true", "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#], "Windows"),
      (["ENABLE_MACOS": "true", "MACOS_SWIFT_VERSIONS": #"["6.3"]"#], "macOS"),
    ]
  )
  func enableFlagSelectsPlatform(environment: [String: String], platform: String) throws {
    let generated = try Generator.run(environment)
    #expect(Set(generated.platforms) == [platform])
  }

  @Test("Every platform disabled generates nothing, without failing")
  func allDisabled() throws {
    let generated = try Generator.run()
    #expect(generated.count == 0)
    #expect(generated.exitCode == 0)
  }

  @Test("Linux and Windows are the defaults")
  func defaults() throws {
    let generated = try Generator.run(includePlatformDefaults: true)
    #expect(Set(generated.platforms) == ["Linux", "Windows"])
  }
}

@Suite("Version lists")
struct VersionListTests {
  @Test("The version list drives one entry each")
  func versionList() throws {
    let generated = try Generator.run(["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.2","6.3"]"#])
    #expect(generated.versions == ["6.2", "6.3"])
  }

  @Test("A version list may be written as YAML")
  func yamlVersionList() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": """
      - "6.2"
      - "6.3"
      """,
    ])
    #expect(generated.versions == ["6.2", "6.3"])
  }

  @Test(
    "A list input that is not a list fails rather than dropping its job kind",
    arguments: [
      (["ENABLE_LINUX": "true", "LINUX_HOST_ARCHS": "x86_64"], "linux_host_archs"),
      (["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": "6.3"], "linux_swift_versions"),
      (["ENABLE_LINUX": "true", "LINUX_DOCKER_CAPABILITIES": "CAP_BPF"], "linux_docker_capabilities"),
      (["ENABLE_WINDOWS": "true", "WINDOWS_SWIFT_VERSIONS": "6.3"], "windows_swift_versions"),
      (["ENABLE_MACOS": "true", "MACOS_SWIFT_VERSIONS": "6.3"], "macos_swift_versions"),
      (["ENABLE_MACOS": "true", "MACOS_XCODE_VERSIONS": "26.3"], "macos_xcode_versions"),
      (
        ["ENABLE_MACOS_SWIFTLY": "true", "MACOS_SWIFTLY_TOOLCHAINS": "main-snapshot"],
        "macos_swiftly_toolchains"
      ),
      (
        ["ENABLE_ANDROID_SDK_BUILD": "true", "ANDROID_NDK_VERSIONS": "r27d"],
        "android_ndk_versions"
      ),
      (["ENABLE_FREEBSD": "true", "FREEBSD_OS_VERSIONS": "14.3"], "freebsd_os_versions"),
      (
        ["ENABLE_LINUX": "true", "ENABLE_CXX_INTEROP": "true", "CXX_INTEROP_SWIFT_VERSIONS": "6.3"],
        "cxx_interop_swift_versions"
      ),
    ]
  )
  func malformedListInputFails(environment: [String: String], expectedName: String) throws {
    // Every list input is a string carrying JSON, so a caller can write a bare
    // scalar. Reading one with `jq -r '.[]'` in a process substitution fails
    // invisibly: set -e does not see it, the loop body never runs, and Windows
    // fills the matrix so the empty-matrix guard does not fire either. The job kind
    // is then absent from a run that reports success.
    var variables = environment
    variables["ENABLE_WINDOWS"] = "true"
    let generated = try Generator.run(variables)
    #expect(generated.exitCode != 0)
    #expect(generated.count == 0)
    #expect(generated.standardError.contains(expectedName))
  }

  @Test("A list input that is not valid YAML fails")
  func unparseableListInputFails() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3""#,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("linux_swift_versions"))
  }
}

@Suite("OS inputs")
struct OSInputTests {
  @Test("Each platform's OS takes a single value")
  func singleValue() throws {
    let linux = try Generator.run([
      "ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#, "LINUX_OS": "jammy",
    ])
    #expect(linux.entries.first?.swiftBuild?.container?.image == "swift:6.3-jammy")

    let macOS = try Generator.run([
      "ENABLE_MACOS": "true", "MACOS_SWIFT_VERSIONS": #"["6.3"]"#, "MACOS_OS": "sequoia",
    ])
    #expect(macOS.entries.first?.runner == ["self-hosted", "macos", "sequoia", "ARM64", "general"])

    let windows = try Generator.run([
      "ENABLE_WINDOWS": "true", "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#, "WINDOWS_OS": "windows-11-arm",
    ])
    #expect(windows.entries.first?.runner == ["windows-11-arm"])
  }

  @Test("A single value is used as written, not as YAML would rewrite it")
  func singleValueIsNotRoundTripped() throws {
    // The input carries YAML so that it can also hold a list, but only a list is
    // taken from the parse: YAML reads 24.10 as the number 24.1, and no image is
    // tagged 6.3-24.1.
    let linux = try Generator.run([
      "ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#, "LINUX_OS": "24.10",
    ])
    #expect(linux.entries.first?.swiftBuild?.container?.image == "swift:6.3-24.10")

    // The macOS pools are self-hosted, so a rewritten label names a pool that does
    // not exist and the job queues until it times out.
    let macOS = try Generator.run([
      "ENABLE_MACOS": "true", "MACOS_SWIFT_VERSIONS": #"["6.3"]"#, "MACOS_OS": "26.10",
    ])
    #expect(macOS.entries.first?.runner == ["self-hosted", "macos", "26.10", "ARM64", "general"])
  }

  @Test("One OS leaves the job names alone, however it is written")
  func oneOSDoesNotRenameJobs() throws {
    // The OS is appended to a name only when a platform has more than one
    // configured. Job names are what branch protection matches on, so one OS -
    // written either way - has to produce the bare name.
    func names(_ osInputs: [String: String]) throws -> [String] {
      var environment = [
        "ENABLE_LINUX": "true",
        "ENABLE_MACOS": "true",
        "ENABLE_WINDOWS": "true",
        "ENABLE_CXX_INTEROP": "true",
        "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
        "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
        "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#,
      ]
      for (key, value) in osInputs {
        environment[key] = value
      }
      return try Generator.run(environment).names
    }

    let expected = [
      "Linux Swift 6.3", "macOS Swift 6.3", "Windows Swift 6.3", "Cxx interop Swift 6.3",
    ]
    #expect(try names([:]) == expected)
    #expect(
      try names(["LINUX_OS": "jammy", "MACOS_OS": "sequoia", "WINDOWS_OS": "windows-11-arm"])
        == expected
    )
    #expect(
      try names([
        "LINUX_OS": #"["jammy"]"#,
        "MACOS_OS": #"["sequoia"]"#,
        "WINDOWS_OS": #"["windows-11-arm"]"#,
      ]) == expected
    )
  }

  @Test("A distribution written as a list of one is the distribution")
  func listOfOneIsTheSameAsNamingIt() throws {
    // How the input was written must not change what runs: a caller who brackets the
    // runner's own distribution gets what naming it bare gets, and a caller who
    // brackets another one gets the image for it.
    let defaultAsList = try Generator.run([
      "ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#, "LINUX_OS": #"["noble"]"#,
    ])
    #expect(defaultAsList.entries.first?.swiftBuild?.container == nil)

    let defaultAsValue = try Generator.run([
      "ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#, "LINUX_OS": "noble",
    ])
    #expect(defaultAsValue.entries.first?.swiftBuild?.container == nil)

    let otherAsList = try Generator.run([
      "ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#, "LINUX_OS": #"["jammy"]"#,
    ])
    #expect(otherAsList.entries.first?.swiftBuild?.container?.image == "swift:6.3-jammy")
  }

  @Test(
    "An OS that is neither a single value nor a list fails",
    arguments: [
      ("LINUX_OS", "linux_os"),
      ("MACOS_OS", "macos_os"),
      ("WINDOWS_OS", "windows_os"),
    ]
  )
  func malformedOSInputFails(key: String, name: String) throws {
    // Unterminated YAML parses as neither, so treating it as a single value would
    // name an OS spelled `["jammy"` and the job would fail somewhere far from the
    // input that caused it.
    let unparseable = try Generator.run([key: #"["jammy""#, "ENABLE_WINDOWS": "true"])
    #expect(unparseable.exitCode != 0)
    #expect(unparseable.count == 0)
    #expect(unparseable.standardError.contains(name))

    // A map names no OS at all.
    let map = try Generator.run([key: "jammy: true", "ENABLE_WINDOWS": "true"])
    #expect(map.exitCode != 0)
    #expect(map.standardError.contains(name))
  }

  @Test(
    "A malformed OS is reported as the input that carried it",
    arguments: [
      ("LINUX_OS", "linux_os"),
      ("MACOS_OS", "macos_os"),
      ("WINDOWS_OS", "windows_os"),
    ]
  )
  func malformedOSInputNamesTheInput(key: String, name: String) throws {
    // The value is parsed from stdin, so the parser's own message names `-` and a
    // line within it: a caller reading it learns neither which of their inputs was
    // wrong nor what it was set to.
    let generated = try Generator.run([key: #"["jammy""#, "ENABLE_WINDOWS": "true"])
    #expect(generated.standardError.contains(name))
    #expect(generated.standardError.contains(#"["jammy""#))
    #expect(!generated.standardError.contains("bad file"))
  }
}

@Suite("Minimum version detection")
struct MinimumVersionTests {
  @Test("The manifest's tools version filters older versions out")
  func detectedFromManifest() throws {
    let generated = try Generator.run(
      ["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.1","6.2","6.3"]"#],
      manifests: ["Package.swift": Generator.manifest(toolsVersion: "6.2")]
    )
    #expect(generated.versions == ["6.2", "6.3"])
  }

  @Test("The lowest of all manifests wins")
  func lowestManifestWins() throws {
    let generated = try Generator.run(
      ["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.0","6.1","6.2"]"#],
      manifests: [
        "Package.swift": Generator.manifest(toolsVersion: "6.2"),
        "Package@swift-6.1.swift": Generator.manifest(toolsVersion: "6.1"),
      ]
    )
    #expect(generated.versions == ["6.1", "6.2"])
  }

  @Test("An explicit minimum overrides the manifest")
  func explicitMinimum() throws {
    let generated = try Generator.run(
      [
        "ENABLE_LINUX": "true",
        "LINUX_SWIFT_VERSIONS": #"["6.1","6.2","6.3"]"#,
        "MINIMUM_SWIFT_VERSION": "6.3",
      ],
      manifests: ["Package.swift": Generator.manifest(toolsVersion: "6.1")]
    )
    #expect(generated.versions == ["6.3"])
  }

  @Test("A minimum of none disables filtering")
  func noneDisablesFiltering() throws {
    let generated = try Generator.run(
      [
        "ENABLE_LINUX": "true",
        "LINUX_SWIFT_VERSIONS": #"["6.1","6.3"]"#,
        "MINIMUM_SWIFT_VERSION": "none",
      ],
      manifests: ["Package.swift": Generator.manifest(toolsVersion: "6.3")]
    )
    #expect(generated.versions == ["6.1", "6.3"])
  }

  @Test("Nightlies are never filtered out")
  func nightliesSurviveFiltering() throws {
    let generated = try Generator.run(
      ["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.1","nightly-main","nightly-release"]"#],
      manifests: ["Package.swift": Generator.manifest(toolsVersion: "6.3")]
    )
    #expect(generated.versions == ["nightly-main", "nightly-release"])
  }
}

@Suite("A kind the minimum version empties")
struct EmptiedByTheMinimumTests {
  // Dropping some of a kind's versions is what the filter is for. Dropping all of
  // them leaves a kind the caller enabled contributing nothing, and the run still
  // reports success: the whole-matrix guard fires only when no other kind produced
  // anything, so any other enabled platform hides it.

  @Test(
    "An enabled kind the filter empties fails, naming the kind",
    arguments: [
      ("ENABLE_CXX_INTEROP", "CXX_INTEROP_SWIFT_VERSIONS", "enable_cxx_interop"),
      (
        "ENABLE_LINUX_STATIC_SDK_BUILD", "LINUX_STATIC_SDK_VERSIONS",
        "enable_linux_static_sdk_build"
      ),
      ("ENABLE_WASM_SDK_BUILD", "WASM_SDK_VERSIONS", "enable_wasm_sdk_build"),
      (
        "ENABLE_EMBEDDED_WASM_SDK_BUILD", "EMBEDDED_WASM_SDK_VERSIONS",
        "enable_embedded_wasm_sdk_build"
      ),
      ("ENABLE_ANDROID_SDK_BUILD", "ANDROID_SDK_VERSIONS", "enable_android_sdk_build"),
      ("ENABLE_LINUX", "LINUX_SWIFT_VERSIONS", "enable_linux"),
      ("ENABLE_WINDOWS", "WINDOWS_SWIFT_VERSIONS", "enable_windows"),
      ("ENABLE_MACOS", "MACOS_SWIFT_VERSIONS", "enable_macos"),
    ]
  )
  func emptiedKindFails(enableKey: String, versionsKey: String, reported: String) throws {
    // A second kind runs alongside on a version that survives, so the matrix is
    // not empty and the guard at the end cannot be what fails the run.
    var environment = ["MINIMUM_SWIFT_VERSION": "6.2"]
    if enableKey == "ENABLE_LINUX" {
      environment["ENABLE_WINDOWS"] = "true"
      environment["WINDOWS_SWIFT_VERSIONS"] = #"["6.3"]"#
    } else {
      environment["ENABLE_LINUX"] = "true"
      environment["LINUX_SWIFT_VERSIONS"] = #"["6.3"]"#
    }
    environment[enableKey] = "true"
    environment[versionsKey] = #"["6.1"]"#

    let generated = try Generator.run(environment)
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains(reported), "\(generated.standardError)")
    // The versions that went and the minimum that took them are what a caller
    // needs to act; a status alone says only that something went wrong.
    #expect(generated.standardError.contains("6.1"), "\(generated.standardError)")
    #expect(generated.standardError.contains("6.2"), "\(generated.standardError)")
    #expect(generated.standardError.contains("minimum_swift_version"), "\(generated.standardError)")
    // The companion kind means the whole-matrix guard has entries to see, so this
    // has to be the new check rather than the old one firing on an empty matrix.
    #expect(!generated.standardError.contains("No matrix entries"), "\(generated.standardError)")

    // The same run with the kind's versions raised passes, so the failure above is
    // the filter and not something else the environment got wrong.
    var runnable = environment
    runnable[versionsKey] = #"["6.3"]"#
    let raised = try Generator.run(runnable)
    #expect(raised.exitCode == 0, "\(raised.standardError)")
    #expect(!raised.entries.isEmpty)
  }

  @Test("The default Cxx-interop version is filtered like any other")
  func defaultedVersionIsChecked() throws {
    // The check names no version: it defaults to the newest release in the Linux
    // list, which a newer manifest puts below the minimum. This is what a caller
    // bumping swift-tools-version ahead of the released toolchains hits, and the
    // Linux and Windows nightlies survive to keep the matrix non-empty.
    let generated = try Generator.run(
      ["ENABLE_CXX_INTEROP": "true"],
      manifests: ["Package.swift": Generator.manifest(toolsVersion: "6.4")],
      includePlatformDefaults: true
    )
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("enable_cxx_interop"), "\(generated.standardError)")
    #expect(generated.standardError.contains("6.3"), "\(generated.standardError)")
  }

  @Test(
    "A label the filter empties fails, naming the label",
    arguments: [
      // Every site that filters a label's own versions: the Linux, macOS and
      // Windows blocks, and the shared emitter behind the SDK builds.
      ("LINUX_COMMAND", "linux_command", ["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.1","6.3"]"#]),
      ("MACOS_COMMAND", "macos_command", ["ENABLE_MACOS": "true", "MACOS_SWIFT_VERSIONS": #"["6.1","6.3"]"#]),
      (
        "WINDOWS_COMMAND", "windows_command",
        ["ENABLE_WINDOWS": "true", "WINDOWS_SWIFT_VERSIONS": #"["6.1","6.3"]"#]
      ),
      (
        "WASM_SDK_COMMAND", "wasm_sdk_command",
        ["ENABLE_WASM_SDK_BUILD": "true", "WASM_SDK_VERSIONS": #"["6.1","6.3"]"#]
      ),
    ]
  )
  func emptiedLabelFails(
    commandKey: String,
    reported: String,
    enables: [String: String]
  ) throws {
    // The label's own versions are intersected with the kind's list before the
    // filter runs, so the filter can empty one label while the others still run:
    // the command the caller named is absent from a matrix that is not empty.
    var environment = enables
    environment[commandKey] = """
      current: swift test
      legacy:
        command: swift test --legacy
        versions: ["6.1"]
      """
    environment["MINIMUM_SWIFT_VERSION"] = "6.2"
    let generated = try Generator.run(environment)
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains(reported), "\(generated.standardError)")
    #expect(generated.standardError.contains("legacy"), "\(generated.standardError)")
    #expect(generated.standardError.contains("6.2"), "\(generated.standardError)")
    #expect(generated.standardError.contains("minimum_swift_version"), "\(generated.standardError)")
    // The other label runs on 6.3, so the matrix this label is missing from is not
    // empty: the guard at the end cannot be what failed the run.
    #expect(!generated.standardError.contains("No matrix entries"), "\(generated.standardError)")

    // Widening the label's own versions is the one change that fixes it, so the
    // failure above is that list and not the rest of the configuration.
    var widened = environment
    widened[commandKey] = """
      current: swift test
      legacy:
        command: swift test --legacy
        versions: ["6.3"]
      """
    let fixed = try Generator.run(widened)
    #expect(fixed.exitCode == 0, "\(fixed.standardError)")
    #expect(fixed.names.contains { $0.hasPrefix("legacy ") }, "\(fixed.names)")

    // Without the enable the kind runs nothing, so the label loses nothing.
    var disabled = environment
    for key in enables.keys where key.hasPrefix("ENABLE_") {
      disabled[key] = "false"
    }
    let off = try Generator.run(disabled)
    #expect(off.exitCode == 0, "\(off.standardError)")
  }

  @Test("A label keeping one version is not an emptied label")
  func partiallyFilteredLabelSurvives() throws {
    // Losing a version the package cannot build on is the filter working. Only a
    // label left with nothing is a job the caller asked for and did not get.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.1","6.2","6.3"]"#,
      "MINIMUM_SWIFT_VERSION": "6.2",
      "LINUX_COMMAND": """
        current: swift test
        legacy:
          command: swift test --legacy
          versions: ["6.1", "6.2"]
        """,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.names.contains("legacy Linux Swift 6.2"))
    #expect(!generated.names.contains("legacy Linux Swift 6.1"))
  }

  @Test("A macOS label naming an Xcode version is not an emptied label")
  func xcodeLabelIsNotEmptied() throws {
    // The Xcode list names Xcodes, which the filter never sees. A label selecting
    // one is fully served by the Xcode pass, so failing it would refuse a
    // configuration that produces exactly the jobs the caller asked for.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "MACOS_XCODE_VERSIONS": #"["latest-beta"]"#,
      "MINIMUM_SWIFT_VERSION": "6.2",
      "MACOS_COMMAND": """
        test: xcrun swift test
        beta:
          command: xcrun swift build
          versions: ["latest-beta"]
        """,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.names.contains("beta macOS Xcode latest-beta"))
  }

  @Test("A kind that is off keeps a version list the filter would empty")
  func disabledKindIsSilent() throws {
    // A kind nobody enabled runs nothing, so a list below the minimum costs it
    // nothing - and failing there would take down the kinds that are on.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "MINIMUM_SWIFT_VERSION": "6.3",
      "ENABLE_CXX_INTEROP": "false",
      "CXX_INTEROP_SWIFT_VERSIONS": #"["6.1"]"#,
      "ENABLE_WASM_SDK_BUILD": "false",
      "WASM_SDK_VERSIONS": #"["6.1"]"#,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.names == ["Linux Swift 6.3"])
  }

  @Test("The fork guard is a skip rather than an emptied kind")
  func forkGuardIsNotAnEmptiedKind() throws {
    // The guard withholds macOS because this repository cannot reach the pools, so
    // the caller did not ask for macOS here. Failing would take down every fork of
    // a repository whose macOS list happens to sit below its own minimum.
    //
    // Linux runs alongside on a version that survives, so the matrix is not empty
    // either way: what the fork must not get is the emptied-kind failure.
    let fork = try Generator.run([
      "ENABLE_MACOS": "true",
      "ENABLE_MACOS_SWIFTLY": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.1"]"#,
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "MINIMUM_SWIFT_VERSION": "6.3",
      "MACOS_REPOSITORY_OWNER": "apple",
      "GITHUB_REPOSITORY_OWNER": "a-fork",
    ])
    #expect(fork.exitCode == 0, "\(fork.standardError)")
    #expect(fork.names == ["Linux Swift 6.3"])

    // The same configuration on the owning repository is an emptied kind. The
    // matrix is non-empty in both runs, so this is the new check rather than the
    // whole-matrix guard, and the pass above is the fork guard rather than the
    // check having been dropped.
    let owner = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.1"]"#,
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "MINIMUM_SWIFT_VERSION": "6.3",
      "MACOS_REPOSITORY_OWNER": "apple",
      "GITHUB_REPOSITORY_OWNER": "apple",
    ])
    #expect(owner.exitCode != 0)
    #expect(owner.standardError.contains("enable_macos"), "\(owner.standardError)")
    #expect(!owner.standardError.contains("No matrix entries"), "\(owner.standardError)")
  }

  @Test("Toolchain mode suppresses the command-only kinds rather than failing them")
  func toolchainsModeIsNotAnEmptiedKind() throws {
    // The mode clears those enables itself, so the caller did not ask for them
    // here either - even with version lists the filter would empty.
    let generated = try Generator.run([
      "MATRIX_MODE": "toolchains",
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "MINIMUM_SWIFT_VERSION": "6.3",
      "ENABLE_CXX_INTEROP": "true",
      "CXX_INTEROP_SWIFT_VERSIONS": #"["6.1"]"#,
      "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
      "LINUX_STATIC_SDK_VERSIONS": #"["6.1"]"#,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.names == ["Linux Swift 6.3"])
  }

  @Test("Nothing enabled is still an empty matrix rather than a failure")
  func nothingEnabledStaysLegitimate() throws {
    // Every version list here sits below the minimum, and none of them belongs to
    // a kind that is on.
    let generated = try Generator.run([
      "ENABLE_LINUX": "false",
      "ENABLE_WINDOWS": "false",
      "MINIMUM_SWIFT_VERSION": "6.3",
      "LINUX_SWIFT_VERSIONS": #"["6.1"]"#,
      "WINDOWS_SWIFT_VERSIONS": #"["6.1"]"#,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.count == 0)
    #expect(generated.standardError.contains("nothing is enabled"))
  }
}

@Suite("Toolchain resolution")
struct ToolchainResolutionTests {
  @Test("A stable version needs no resolved forms")
  func stableVersion() throws {
    let generated = try Generator.run(["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#])
    let build = try #require(generated.entries.first?.swiftBuild)
    #expect(build.swiftVersion == "6.3")
    #expect(build.toolchain == nil)
    #expect(build.swiftly == nil)
  }

  @Test("nightly-release keeps the label and carries both resolved forms")
  func nightlyRelease() throws {
    let generated = try Generator.run(["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["nightly-release"]"#])
    let build = try #require(generated.entries.first?.swiftBuild)
    #expect(build.swiftVersion == "nightly-release")
    #expect(build.toolchain == "nightly-6.4.x")
    // The branch token names the snapshot's own directory under dev/, and swiftly's
    // release-snapshot grammar takes it whole, so it is passed through.
    #expect(build.swiftly == "6.4.x-snapshot")
  }

  @Test("The branch token is data, so it can be moved at a branch cut")
  func tokenIsConfigurable() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["nightly-release"]"#,
      "NIGHTLY_RELEASE_TOKEN": "6.5",
    ])
    let build = try #require(generated.entries.first?.swiftBuild)
    #expect(build.toolchain == "nightly-6.5")
    #expect(build.swiftly == "6.5-snapshot")
  }

  @Test("nightly-main resolves only the swiftly selector")
  func nightlyMain() throws {
    let generated = try Generator.run(["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["nightly-main"]"#])
    let build = try #require(generated.entries.first?.swiftBuild)
    #expect(build.toolchain == nil, "the toolchain matches the label, so it should be omitted")
    #expect(build.swiftly == "main-snapshot")
  }

  @Test(
    "A branch named directly resolves like the alias",
    arguments: [("nightly-6.4.x", "6.4.x-snapshot"), ("nightly-6.2", "6.2-snapshot")]
  )
  func literalBranchNightly(version: String, expectedSelector: String) throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["\#(version)"]"#,
    ])
    #expect(generated.entries.first?.swiftBuild?.swiftly == expectedSelector)
  }
}

@Suite("Linux runners and containers")
struct LinuxTests {
  @Test("Architecture selects the runner")
  func architectureToRunner() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_HOST_ARCHS": #"["x86_64","aarch64"]"#,
    ])
    #expect(generated.entries.map { $0.runner.first } == ["ubuntu-24.04", "ubuntu-24.04-arm"])
  }

  @Test("Linux is native until Docker is asked for")
  func nativeByDefault() throws {
    let native = try Generator.run(["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#])
    #expect(native.entries.first?.swiftBuild?.container == nil)

    let containerized = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_USE_DOCKER": "true",
    ])
    #expect(containerized.entries.first?.swiftBuild?.container?.image == "swift:6.3-noble")
  }

  @Test("Every job kind runs on the architecture that was configured")
  func architectureAppliesToEveryKind() throws {
    // The single-entry kinds do not fan out, so nothing but this makes them
    // follow linux_host_archs. An aarch64-only caller must not get x86_64 jobs
    // that pass without testing the architecture it ships.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "ENABLE_CXX_INTEROP": "true",
      "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
      "LINUX_HOST_ARCHS": #"["aarch64"]"#,
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "CXX_INTEROP_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_STATIC_SDK_VERSIONS": #"["6.3"]"#,
    ])
    #expect(generated.count == 3)
    for entry in generated.entries {
      #expect(entry.runner == ["ubuntu-24.04-arm"], "\(entry.name) ignored linux_host_archs")
    }
  }

  @Test("Naming a non-default Linux OS implies a container")
  func nonDefaultOSImpliesContainer() throws {
    // The OS names a container image. Left native, the job would run on the
    // runner's own distribution and pass, having tested nothing about the one
    // asked for.
    let named = try Generator.run([
      "ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#, "LINUX_OS": "jammy",
    ])
    #expect(named.entries.first?.swiftBuild?.container?.image == "swift:6.3-jammy")

    let defaulted = try Generator.run([
      "ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#, "LINUX_OS": "noble",
    ])
    #expect(defaulted.entries.first?.swiftBuild?.container == nil)
  }

  @Test("A version list entry that is neither a number nor a nightly label fails")
  func nonNumericVersionFails() throws {
    // It would otherwise reach the arithmetic in version_gte and abort with a
    // bash unbound-variable error naming neither the input nor the value.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["latest-beta","6.3"]"#,
      "MINIMUM_SWIFT_VERSION": "6.1",
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("latest-beta"))
    // The arithmetic in version_gte also aborts non-zero, with "unbound
    // variable", so a message-and-status assertion alone would pass either way.
    // The test has to show the run stopped before reaching it.
    #expect(!generated.standardError.contains("unbound variable"))
  }

  @Test("A release-branch nightly runs natively, like every other version")
  func releaseBranchNightlyIsNative() throws {
    // The branch token is the snapshot's published directory under dev/, so swiftly
    // installs a release-branch nightly from the selector alone. Containerizing it
    // would swap the toolchain under test for the image's own and cost a pull.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3","nightly-release","nightly-main"]"#,
    ])
    for name in ["Linux Swift 6.3", "Linux Swift nightly-main", "Linux Swift nightly-release"] {
      #expect(generated.entry(named: name)?.swiftBuild?.container == nil, "\(name) was containerized")
    }
    #expect(generated.entry(named: "Linux Swift nightly-release")?.swiftBuild?.swiftly == "6.4.x-snapshot")
  }

  @Test(
    "Nightly images come from the nightly registry",
    arguments: [
      ("nightly-release", "swiftlang/swift:nightly-6.4.x-noble"),
      ("nightly-main", "swiftlang/swift:nightly-main-noble"),
      ("6.3", "swift:6.3-noble"),
    ]
  )
  func containerImages(version: String, expectedImage: String) throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_USE_DOCKER": "true",
      "LINUX_SWIFT_VERSIONS": #"["\#(version)"]"#,
    ])
    #expect(generated.entries.first?.swiftBuild?.container?.image == expectedImage)
  }

  @Test("An OS list forces Docker and multiplies the entries")
  func osList() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_OS": #"["jammy","noble"]"#,
    ])
    #expect(generated.count == 2)
    #expect(
      generated.entries.compactMap { $0.swiftBuild?.container?.image } == [
        "swift:6.3-jammy", "swift:6.3-noble",
      ]
    )
    #expect(generated.names == ["Linux Swift 6.3 jammy", "Linux Swift 6.3 noble"])
  }

  @Test("Container capabilities and security options are carried")
  func containerKnobs() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_USE_DOCKER": "true",
      "LINUX_DOCKER_CAPABILITIES": #"["CAP_BPF"]"#,
      "LINUX_DOCKER_SECURITY_OPTIONS": #"["apparmor=unconfined"]"#,
    ])
    let container = try #require(generated.entries.first?.swiftBuild?.container)
    #expect(container.capabilities == ["CAP_BPF"])
    #expect(container.securityOptions == ["apparmor=unconfined"])
  }

  @Test("A Dockerfile implies container mode and keeps the base image")
  func dockerfileImpliesContainer() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_DOCKERFILE": "docker/ci.Dockerfile",
    ])
    let container = try #require(generated.entries.first?.swiftBuild?.container)
    #expect(container.dockerfile == "docker/ci.Dockerfile")
    #expect(container.image == "swift:6.3-noble")
  }

  @Test("Unset container knobs are omitted rather than emitted empty")
  func knobsOmittedWhenUnset() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_USE_DOCKER": "true",
    ])
    let container = try #require(generated.entries.first?.swiftBuild?.container)
    #expect(container.dockerfile == nil)
    #expect(container.capabilities == nil)
    #expect(container.securityOptions == nil)
  }
}

@Suite("Commands, arguments and overrides")
struct CommandTests {
  @Test("The build and pre-build commands are carried")
  func commandsCarried() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_COMMAND": "swift test --verbose",
      "LINUX_SETUP_COMMAND": "cd sub",
    ])
    #expect(generated.entries.first?.command == "swift test --verbose")
    #expect(generated.entries.first?.setupCommand == "cd sub")
  }

  @Test("Releases take swift_flags and nightlies take swift_nightly_flags")
  func flagSelection() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3","nightly-main"]"#,
      "SWIFT_FLAGS": "-Xswiftc -DRELEASE",
      "SWIFT_NIGHTLY_FLAGS": "-Xswiftc -DNIGHTLY",
    ])
    #expect(generated.entries[0].commandArguments == ["-Xswiftc", "-DRELEASE"])
    #expect(generated.entries[1].commandArguments == ["-Xswiftc", "-DNIGHTLY"])
  }

  @Test("A string override appends arguments and leaves the command alone")
  func stringOverride() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.2","6.3"]"#,
      "LINUX_VERSION_OVERRIDES": #"{"6.3": "-Xswiftc -warnings-as-errors"}"#,
    ])
    #expect(generated.entries[0].commandArguments == [], "an untargeted version is untouched")
    #expect(generated.entries[1].commandArguments == ["-Xswiftc", "-warnings-as-errors"])
    #expect(generated.entries[1].command == "swift test")
  }

  @Test("An object override can replace the command")
  func objectOverride() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_VERSION_OVERRIDES": """
      6.3:
        command: swift build
        arguments: --explicit-target-dependency-import-check error
      """,
    ])
    #expect(generated.entries.first?.command == "swift build")
    #expect(
      generated.entries.first?.commandArguments == [
        "--explicit-target-dependency-import-check", "error",
      ]
    )
  }

  @Test(
    "A malformed overrides object fails, naming the input and showing the value",
    arguments: [
      (#"{"6.3":"#, #"{"6.3":"#),
      (#"["6.3"]"#, #"["6.3"]"#),
      ("6.3", "6.3"),
      (#"{"6.3": ["-Xswiftc","-warnings-as-errors"]}"#, #"["-Xswiftc","-warnings-as-errors"]"#),
      (#"{"6.3": {"argument": "-Xswiftc"}}"#, #"{"argument":"-Xswiftc"}"#),
      (#"{"6.3": null}"#, "6.3: null"),
      (#"{"6.3": {"command": 5}}"#, #"{"command":5}"#),
    ]
  )
  func malformedOverridesFail(overrides: String, reported: String) throws {
    // Every one of these reads as no override at all, so the job runs without the
    // arguments it was asked to carry and still passes - which is how a repository
    // loses warnings-as-errors.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_VERSION_OVERRIDES": overrides,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.count == 0)
    #expect(generated.standardError.contains("linux_version_overrides"))
    #expect(generated.standardError.contains(reported))
    // The value is parsed from stdin, so the parser's own message names `-` and a
    // line within it: a caller reading it learns neither which input was wrong nor
    // what it was set to.
    #expect(!generated.standardError.contains("bad file"))
  }

  @Test(
    "Every platform's overrides input is checked",
    arguments: [
      ("LINUX_VERSION_OVERRIDES", "linux_version_overrides"),
      ("WINDOWS_VERSION_OVERRIDES", "windows_version_overrides"),
      ("MACOS_VERSION_OVERRIDES", "macos_version_overrides"),
    ]
  )
  func everyOverridesInputIsChecked(key: String, name: String) throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      key: #"["6.3"]"#,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.count == 0)
    #expect(generated.standardError.contains(name))
  }

  @Test("An absent override is not a malformed one")
  func absenceIsNotMalformation() throws {
    // A version the map does not name has nothing to add, and neither does an input
    // left blank. Failing on either would take down the versions nobody overrode.
    let oneVersionNamed = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.2","6.3"]"#,
      "LINUX_VERSION_OVERRIDES": #"{"6.3": "-Xswiftc -warnings-as-errors"}"#,
    ])
    #expect(oneVersionNamed.exitCode == 0)
    try #require(oneVersionNamed.count == 2)
    #expect(oneVersionNamed.entries[0].commandArguments == [])
    #expect(oneVersionNamed.entries[1].commandArguments == ["-Xswiftc", "-warnings-as-errors"])

    for blank in ["", " ", "\n", "null"] {
      let generated = try Generator.run([
        "ENABLE_LINUX": "true",
        "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
        "LINUX_VERSION_OVERRIDES": blank,
      ])
      #expect(generated.exitCode == 0, "a blank input carries no override")
      try #require(generated.count == 1)
      #expect(generated.entries[0].commandArguments == [])
      #expect(generated.entries[0].command == "swift test")
    }
  }

  @Test(
    "Environment variables reach the entry",
    arguments: [
      (["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#, "LINUX_ENV_VARS": #"{"FOO":"bar"}"#], "bar"),
      (["ENABLE_WINDOWS": "true", "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#, "WINDOWS_ENV_VARS": "FOO: baz"], "baz"),
    ]
  )
  func environmentVariables(environment: [String: String], expected: String) throws {
    let generated = try Generator.run(environment)
    #expect(generated.entries.first?.env["FOO"] == expected)
  }
}

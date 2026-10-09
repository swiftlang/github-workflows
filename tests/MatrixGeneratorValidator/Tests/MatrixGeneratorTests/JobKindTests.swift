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
import MatrixTestSupport
import Testing

@Suite("SDK builds")
struct SDKTests {
  @Test(
    "Each SDK kind declares its type",
    arguments: [
      ("ENABLE_LINUX_STATIC_SDK_BUILD", "LINUX_STATIC_SDK_VERSIONS", "static-linux"),
      ("ENABLE_WASM_SDK_BUILD", "WASM_SDK_VERSIONS", "wasm"),
      ("ENABLE_EMBEDDED_WASM_SDK_BUILD", "EMBEDDED_WASM_SDK_VERSIONS", "embedded-wasm"),
    ]
  )
  func sdkType(enableKey: String, versionsKey: String, expectedType: String) throws {
    let generated = try Generator.run([enableKey: "true", versionsKey: #"["6.3"]"#])
    #expect(generated.entries.first?.swiftBuild?.sdk?.type == expectedType)
  }

  @Test("An SDK entry keeps the label and carries the toolchain the SDK script needs")
  func labelAndToolchain() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
      "LINUX_STATIC_SDK_VERSIONS": #"["nightly-release"]"#,
    ])
    let build = try #require(generated.entries.first?.swiftBuild)
    #expect(build.swiftVersion == "nightly-release")
    // The SDK script derives swift.org paths from this, so the label alone would
    // give it dev/release.
    #expect(build.toolchain == "nightly-6.4.x")
  }

  @Test("The SDK pre-build command is carried")
  func preBuildCommand() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
      "LINUX_STATIC_SDK_VERSIONS": #"["6.3"]"#,
      "LINUX_STATIC_SDK_SETUP_COMMAND": "cd sub",
    ])
    // The SDK script builds in the working directory, so this is the only way to
    // reach a package below the repository root.
    #expect(generated.entries.first?.setupCommand == "cd sub")
  }

  @Test("Android entries carry an NDK version each and the triples")
  func androidNDKAndTriples() throws {
    let generated = try Generator.run([
      "ENABLE_ANDROID_SDK_BUILD": "true",
      "ANDROID_SDK_VERSIONS": #"["6.3"]"#,
      "ANDROID_NDK_VERSIONS": #"["r27d","r28c"]"#,
      "ANDROID_SDK_TRIPLES": #"["aarch64-unknown-linux-android28"]"#,
    ])
    #expect(generated.count == 2)
    #expect(generated.entries.compactMap { $0.swiftBuild?.sdk?.ndkVersion } == ["r27d", "r28c"])
    #expect(generated.entries.first?.swiftBuild?.sdk?.triples == ["aarch64-unknown-linux-android28"])
  }

  @Test("Emulator checks ask the build for test binaries")
  func emulatorRequestsTestBinaries() throws {
    let withoutEmulator = try Generator.run([
      "ENABLE_ANDROID_SDK_BUILD": "true",
      "ANDROID_SDK_VERSIONS": #"["6.3"]"#,
      "ANDROID_NDK_VERSIONS": #"["r27d"]"#,
    ])
    #expect(withoutEmulator.entries.first?.androidEmulator == false)
    #expect(withoutEmulator.entries.first?.commandArguments == [])

    // The emulator script stages what the build produced, so without this there is
    // nothing to run.
    let withEmulator = try Generator.run([
      "ENABLE_ANDROID_SDK_BUILD": "true",
      "ENABLE_ANDROID_EMULATOR_TESTS": "true",
      "ANDROID_SDK_VERSIONS": #"["6.3"]"#,
      "ANDROID_NDK_VERSIONS": #"["r27d"]"#,
    ])
    #expect(withEmulator.entries.first?.androidEmulator == true)
    #expect(withEmulator.entries.first?.commandArguments == ["--build-tests"])
  }
}

@Suite("Cxx interop")
struct SupplementaryCheckTests {
  @Test("Cxx interop defaults to one version and can enter a subdirectory")
  func cxxInteropScope() throws {
    let generated = try Generator.run([
      "ENABLE_CXX_INTEROP": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.2","6.3"]"#,
      "LINUX_SETUP_COMMAND": "cd sub",
    ])
    #expect(generated.count == 1)
    #expect(generated.entries.first?.swiftBuild?.swiftVersion == "6.3")
    // check-cxx-interop.sh reads the manifest in the working directory.
    #expect(generated.entries.first?.setupCommand == "cd sub")
    #expect(generated.entries.first?.command == "${SCRIPTS_ROOT}/check-cxx-interop.sh")
  }

  @Test("The check runs on the same distribution as the tests")
  func sameDistributionAsTests() throws {
    let generated = try Generator.run([
      "ENABLE_CXX_INTEROP": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_OS": #"["jammy"]"#,
    ])
    let images = Set(generated.entries.compactMap { $0.swiftBuild?.container?.image })
    #expect(images == ["swift:6.3-jammy"])
  }
}

@Suite("Job kinds")
struct JobKindTests {
  @Test("Every kind generates the entries it is enabled for")
  func everyKindGeneratesEntries() throws {
    // A kind whose version list no caller can reach, or whose enable nothing sets,
    // would be unreachable while the generator still offers it.
    let enables = [
      "ENABLE_LINUX_STATIC_SDK_BUILD",
      "ENABLE_WASM_SDK_BUILD",
      "ENABLE_EMBEDDED_WASM_SDK_BUILD",
      "ENABLE_ANDROID_SDK_BUILD",
      "ENABLE_CXX_INTEROP",
    ]
    for enable in enables {
      let generated = try Generator.run([enable: "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#])
      #expect(generated.exitCode == 0, "\(enable): \(generated.standardError)")
      #expect(!generated.entries.isEmpty, "\(enable) generated nothing")
      for entry in generated.entries {
        #expect(entry.platform == "Linux", "\(entry.name) is not a Linux entry")
        #expect(entry.command?.isEmpty == false, "\(entry.name) has no command")
        #expect(entry.swiftBuild?.swiftVersion != nil, "\(entry.name) has no toolchain")
      }
    }
  }
}

@Suite("FreeBSD")
struct FreeBSDTests {
  @Test("A FreeBSD entry carries its virtual machine configuration")
  func entryShape() throws {
    let generated = try Generator.run([
      "ENABLE_FREEBSD": "true",
      "FREEBSD_SWIFT_VERSIONS": #"["nightly-main"]"#,
      "FREEBSD_OS_VERSIONS": #"["14.3"]"#,
      "FREEBSD_COMMAND": "swift build",
      "FREEBSD_SETUP_COMMAND": "cd sub",
      "FREEBSD_ENV_VARS": "FOO=bar",
    ])
    let entry = try #require(generated.entries.first)
    #expect(entry.platform == "FreeBSD")
    #expect(entry.freebsd?.osVersion == "14.3")
    #expect(entry.freebsd?.envVars == "FOO=bar")
    #expect(entry.command == "swift build")
    #expect(entry.setupCommand == "cd sub")
    // The executor derives SWIFT_VERSION from this. A FreeBSD entry has neither
    // swift_build nor xcode_build, so without it anything keyed on the version -
    // benchmark thresholds - would look under an empty directory name.
    #expect(entry.freebsd?.swiftVersion == "nightly-main")
    // The toolchain has to be the one built for the OS the job claims to run.
    #expect(entry.freebsd?.swiftURL.contains("freebsd-14") == true)
  }

  @Test("A version other than nightly-main fails rather than mislabeling the job")
  func nonNightlyVersionFails() throws {
    // One FreeBSD toolchain is published and the URL is fixed, so a job named for
    // any other version would report a green check for a toolchain it never used.
    let generated = try Generator.run([
      "ENABLE_FREEBSD": "true",
      "FREEBSD_SWIFT_VERSIONS": #"["6.3"]"#,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("nightly-main"))
  }

  @Test("An OS version with no published toolchain fails rather than running another's")
  func unpublishedOSVersionFails() throws {
    // The tarballs are named by major release and only 14 has one, so a job
    // labeled 15.0 would report a green check for the 14 toolchain.
    let generated = try Generator.run([
      "ENABLE_FREEBSD": "true",
      "FREEBSD_OS_VERSIONS": #"["15.0"]"#,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("15.0"))
  }
}

@Suite("Output modes")
struct OutputModeTests {
  @Test("Toolchain mode omits what the caller supplies instead")
  func toolchainsModeOmitsCommands() throws {
    let generated = try Generator.run([
      "MATRIX_MODE": "toolchains",
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
    ])
    let entry = try #require(generated.entries.first)
    #expect(entry.command == nil)
    #expect(entry.setupCommand == nil)
    #expect(entry.commandArguments == nil)
    // The toolchain itself is still fully described, and env describes what the
    // toolchain needs rather than the work.
    #expect(entry.swiftBuild?.swiftVersion == "6.3")
    #expect(entry.runner == ["ubuntu-24.04"])
  }

  @Test("Toolchain mode suppresses the job kinds that exist only to run a command")
  func toolchainsModeSuppressesJobKinds() throws {
    let generated = try Generator.run([
      "MATRIX_MODE": "toolchains",
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
      "ENABLE_CXX_INTEROP": "true",
      "ENABLE_FREEBSD": "true",
    ])
    #expect(generated.names == ["Linux Swift 6.3"])
  }

  @Test("An empty matrix fails only when something was enabled")
  func emptyMatrixFailsOnlyWhenEnabled() throws {
    // Nothing enabled is legitimate - a caller who disables every platform gets an
    // empty matrix. Something enabled that produced nothing is a mistake, and
    // silence there is a green run that tested nothing.
    let nothingEnabled = try Generator.run()
    #expect(nothingEnabled.exitCode == 0)
    #expect(nothingEnabled.count == 0)

    // Every listed version filtered out by the manifest's tools version.
    let filteredAway = try Generator.run(
      [
        "ENABLE_LINUX": "true",
        "ENABLE_WINDOWS": "true",
        "LINUX_SWIFT_VERSIONS": #"["6.1"]"#,
        "WINDOWS_SWIFT_VERSIONS": #"["6.1"]"#,
      ],
      manifests: ["Package.swift": Generator.manifest(toolsVersion: "6.3")]
    )
    #expect(filteredAway.exitCode != 0)
    #expect(filteredAway.standardError.contains("enable_linux"))

    // A deliberate skip is not a mistake: the fork guard clears macOS, leaving
    // nothing enabled rather than something enabled that produced nothing.
    let forkSkipped = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
      "MACOS_REPOSITORY_OWNER": "apple",
      "GITHUB_REPOSITORY_OWNER": "somefork",
    ])
    #expect(forkSkipped.exitCode == 0)
    #expect(forkSkipped.count == 0)
  }

  @Test("An unknown mode fails rather than guessing")
  func unknownModeFails() throws {
    let generated = try Generator.run(["MATRIX_MODE": "nonsense"])
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("MATRIX_MODE"))
  }

  @Test("YAML is the output format by default")
  func yamlByDefault() throws {
    let result = try Generator.runRaw(["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#])
    #expect(result.standardOutput.hasPrefix("config:"))
  }

  @Test("JSON output can be asked for, which is what a decoder wants")
  func jsonOnRequest() throws {
    let result = try Generator.runRaw([
      "MATRIX_FORMAT": "json",
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
    ])
    #expect(result.standardOutput.hasPrefix("{"))
  }

  @Test("An empty matrix is well formed in both output formats")
  func emptyMatrixInBothFormats() throws {
    let yaml = try Generator.runRaw()
    #expect(yaml.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "config: []")

    // run() asks for JSON and decodes it, so this covers the JSON form through the
    // same path every other test uses.
    let json = try Generator.run()
    #expect(json.count == 0)
    #expect(json.exitCode == 0)
  }

  @Test("An unknown output format fails rather than guessing")
  func unknownFormatFails() throws {
    let result = try Generator.runRaw(["MATRIX_FORMAT": "xml"])
    #expect(result.exitCode != 0)
    #expect(result.standardError.contains("MATRIX_FORMAT"))
  }
}

@Suite("Whole-matrix invariants")
struct InvariantTests {
  /// Everything enabled at once, which is the widest shape the generator produces.
  private func everything() throws -> Generated {
    try Generator.run(
      [
        "ENABLE_MACOS": "true",
        "ENABLE_FREEBSD": "true",
        "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
        "ENABLE_WASM_SDK_BUILD": "true",
        "ENABLE_ANDROID_SDK_BUILD": "true",
        "ENABLE_CXX_INTEROP": "true",
        "ENABLE_MACOS_SWIFTLY": "true",
        "XCODE_SCHEME": "P-Package",
        "XCODE_TARGETS": "[iOS, watchOS]",
        // Two Linux OSes but one Windows OS, so the counts differ: a name built
        // from the wrong platform's count would collide in the uniqueness check.
        "LINUX_OS": #"["jammy","noble"]"#,
        "WINDOWS_OS": #"["windows-2022"]"#,
      ],
      includePlatformDefaults: true
    )
  }

  @Test("Every entry carries what the executor dispatches on")
  func everyEntryIsExecutable() throws {
    let generated = try everything()
    #expect(generated.count >= 15, "expected a substantial matrix, got \(generated.count)")

    for entry in generated.entries {
      #expect(!entry.platform.isEmpty)
      #expect(!entry.name.isEmpty)
      #expect(!entry.runner.isEmpty, "\(entry.name) has no runner")
      #expect(entry.command?.isEmpty == false, "\(entry.name) has no command")
    }
  }

  @Test("Every entry has exactly one toolchain model")
  func oneToolchainModelPerEntry() throws {
    let generated = try everything()
    for entry in generated.entries where entry.platform != "FreeBSD" {
      let models = [entry.swiftBuild != nil, entry.xcodeBuild != nil].filter { $0 }.count
      #expect(models == 1, "\(entry.name) has \(models) toolchain models; the dispatch assumes one")
    }
  }

  @Test("Job names are unique, since they are how a run is read")
  func namesAreUnique() throws {
    let generated = try everything()
    #expect(Set(generated.names).count == generated.count)
  }

  @Test("A job's name does not depend on another platform's OS count")
  func nameDoesNotDependOnAnotherPlatform() throws {
    // The OS suffix is appended when a platform has more than one OS configured.
    // Each platform must count its own: job names are the identity branch
    // protection matches on, so enabling Windows must not rename a Linux job.
    func names(windowsEnabled: Bool, windowsOSVersions: String) throws -> [String] {
      try Generator.run([
        "ENABLE_LINUX": "true",
        "ENABLE_WINDOWS": windowsEnabled ? "true" : "false",
        "ENABLE_CXX_INTEROP": "true",
        "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
        "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#,
        "LINUX_OS": #"["jammy","noble"]"#,
        "WINDOWS_OS": windowsOSVersions,
      ]).names.filter { $0.hasPrefix("Cxx interop") }
    }

    let withoutWindows = try names(windowsEnabled: false, windowsOSVersions: #"["windows-2022"]"#)
    let withOneWindowsOS = try names(windowsEnabled: true, windowsOSVersions: #"["windows-2022"]"#)
    let withTwoWindowsOSes = try names(
      windowsEnabled: true,
      windowsOSVersions: #"["windows-2022","windows-2025"]"#
    )

    #expect(withoutWindows == withOneWindowsOS)
    #expect(withoutWindows == withTwoWindowsOSes)
    // Two Linux OSes are configured, so each name must carry its own.
    #expect(Set(withoutWindows).count == withoutWindows.count)
    #expect(withoutWindows.allSatisfy { $0.hasSuffix("jammy") || $0.hasSuffix("noble") })
  }

  @Test("Supplementary job kinds carry the flags for their version")
  func supplementaryKindsCarryFlags() throws {
    // Each of these kinds builds its own argument list, so each can drop
    // swift_flags independently - and a repository that loses warnings-as-errors
    // stays green.
    let generated = try Generator.run([
      "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
      "ENABLE_WASM_SDK_BUILD": "true",
      "ENABLE_EMBEDDED_WASM_SDK_BUILD": "true",
      "ENABLE_CXX_INTEROP": "true",
      "LINUX_STATIC_SDK_VERSIONS": #"["6.3"]"#,
      "WASM_SDK_VERSIONS": #"["6.3"]"#,
      "EMBEDDED_WASM_SDK_VERSIONS": #"["6.3"]"#,
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "SWIFT_FLAGS": "-Xswiftc -warnings-as-errors",
    ])
    #expect(generated.count == 4)
    for entry in generated.entries {
      #expect(
        entry.commandArguments == ["-Xswiftc", "-warnings-as-errors"],
        "\(entry.name) dropped swift_flags"
      )
    }
  }

  @Test("A nightly version gets the nightly flags, not the release ones")
  func nightlyGetsNightlyFlags() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
      "LINUX_STATIC_SDK_VERSIONS": #"["nightly-main"]"#,
      "SWIFT_FLAGS": "-Xswiftc -warnings-as-errors",
      "SWIFT_NIGHTLY_FLAGS": "--explicit-target-dependency-import-check error",
    ])
    #expect(
      generated.entries.first?.commandArguments
        == ["--explicit-target-dependency-import-check", "error"]
    )
  }

  @Test("An argument containing a glob is passed through, not expanded")
  func argumentsAreNotGlobbed() throws {
    // An unquoted split would expand `--filter *Tests` against the generator's
    // working directory, so the runner would receive several arguments where the
    // caller wrote one.
    let generated = try Generator.run(
      [
        "ENABLE_LINUX": "true",
        "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
        "SWIFT_FLAGS": "--filter *Tests",
      ],
      manifests: ["aTests": "", "bTests": ""]
    )
    #expect(generated.entries.first?.commandArguments == ["--filter", "*Tests"])

    // The macOS-swiftly entries take their flags on a path of their own, so they
    // can glob independently of the Linux entries.
    let swiftly = try Generator.run(
      [
        "ENABLE_LINUX": "true",
        "ENABLE_MACOS_SWIFTLY": "true",
        "LINUX_SWIFT_VERSIONS": #"["nightly-main"]"#,
        "SWIFT_NIGHTLY_FLAGS": "--filter *Tests",
      ],
      manifests: ["aTests": "", "bTests": ""]
    )
    for entry in swiftly.entries {
      #expect(entry.commandArguments == ["--filter", "*Tests"], "\(entry.name) expanded the glob")
    }
  }

  @Test("No Linux kind containerizes a version unless the caller asked for a container")
  func containersOnlyWhenAskedFor() throws {
    // A container swaps the toolchain under test for the image's own and costs a
    // pull, so it is the caller's decision alone. swiftly installs every version the
    // generator produces, nightly-release included, so no kind may reach for one on
    // a version's behalf.
    func kinds(_ extra: [String: String]) throws -> Generated {
      var environment = [
        "ENABLE_LINUX": "true",
        "ENABLE_CXX_INTEROP": "true",
        "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
        "LINUX_SWIFT_VERSIONS": #"["nightly-release"]"#,
        "CXX_INTEROP_SWIFT_VERSIONS": #"["nightly-release"]"#,
        "LINUX_STATIC_SDK_VERSIONS": #"["nightly-release"]"#,
      ]
      for (key, value) in extra {
        environment[key] = value
      }
      return try Generator.run(environment)
    }

    let unasked = try kinds([:])
    #expect(unasked.count == 3)
    for entry in unasked.entries {
      #expect(entry.swiftBuild?.container == nil, "\(entry.name) containerized unasked")
      #expect(entry.swiftBuild?.swiftly == "6.4.x-snapshot", "\(entry.name) carries the wrong selector")
    }

    // Each of the three ways to ask, so a kind that reads only one of them is caught.
    for (ask, image) in [
      (["LINUX_USE_DOCKER": "true"], "swiftlang/swift:nightly-6.4.x-noble"),
      (["LINUX_DOCKERFILE": "docker/ci.Dockerfile"], "swiftlang/swift:nightly-6.4.x-noble"),
      (["LINUX_OS": "jammy"], "swiftlang/swift:nightly-6.4.x-jammy"),
    ] {
      let asked = try kinds(ask)
      for name in ["Linux Swift nightly-release", "Cxx interop Swift nightly-release"] {
        #expect(
          asked.entry(named: name)?.swiftBuild?.container?.image == image,
          "\(name) ignored \(ask)"
        )
      }
      // An SDK entry stays native even then: job-runner-linux.sh refuses an entry
      // carrying both an sdk and a container, since the SDK script fetches a
      // toolchain matched to the SDK rather than using the image's.
      #expect(
        asked.entry(named: "Static Linux SDK Swift nightly-release")?.swiftBuild?.container == nil,
        "the SDK entry containerized under \(ask)"
      )
    }
  }

  @Test("Asking for the Android emulator without the SDK build fails")
  func emulatorWithoutSDKBuildFails() throws {
    // The emulator runs what the SDK build produced, so on its own it yields no
    // jobs at all - a green run that tested nothing.
    let generated = try Generator.run(["ENABLE_ANDROID_EMULATOR_TESTS": "true"])
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("enable_android_sdk_build"))

    // Toolchain mode suppresses both, so it must not fail there.
    let toolchains = try Generator.run([
      "MATRIX_MODE": "toolchains",
      "ENABLE_ANDROID_EMULATOR_TESTS": "true",
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
    ])
    #expect(toolchains.exitCode == 0)
    #expect(toolchains.names == ["Linux Swift 6.3"])
  }

  @Test("An override key naming no version fails rather than losing its arguments")
  func unmatchedOverrideKeyFails() throws {
    // These carry warnings-as-errors for NIO-family repositories. A key left
    // behind by a version rename would otherwise drop them and still pass.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3","nightly-release"]"#,
      "LINUX_VERSION_OVERRIDES": #"{"nightly-next":"-Xswiftc -warnings-as-errors"}"#,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("nightly-next"))
  }

  @Test("A Linux override key may name a version from any enabled Linux list")
  func overrideKeysValidatedAgainstEveryLinuxList() throws {
    // The Cxx-interop and SDK lists are independent of the test sweep, and every
    // one of them draws its arguments from linux_version_overrides. Checking the
    // sweep alone rejects a key naming a version only the Cxx interop check runs.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "ENABLE_CXX_INTEROP": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "CXX_INTEROP_SWIFT_VERSIONS": #"["6.2","6.3"]"#,
      "LINUX_VERSION_OVERRIDES": #"{"6.2":"-Xswiftc -DX"}"#,
    ])
    #expect(generated.exitCode == 0)
    #expect(generated.entry(named: "Cxx interop Swift 6.2")?.commandArguments == ["-Xswiftc", "-DX"])
    #expect(generated.entry(named: "Linux Swift 6.3")?.commandArguments == [])

    // A key naming no enabled list is still rejected.
    let bogus = try Generator.run([
      "ENABLE_LINUX": "true",
      "ENABLE_CXX_INTEROP": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "CXX_INTEROP_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_VERSION_OVERRIDES": #"{"6.2":"-Xswiftc -DX"}"#,
    ])
    #expect(bogus.exitCode != 0)
  }

  @Test(
    "Overrides for a platform that generates nothing warn rather than failing the run",
    arguments: [
      ("MACOS_VERSION_OVERRIDES", "macos_version_overrides"),
      ("WINDOWS_VERSION_OVERRIDES", "windows_version_overrides"),
    ]
  )
  func overridesForDisabledPlatformWarn(key: String, label: String) throws {
    // A disabled platform's version list still holds the generator's defaults, so a
    // key naming none of them has nothing to lose. Failing there takes down every
    // enabled platform's jobs over a setting nothing reads.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      key: #"{"latest-beta":"-Xswiftc -DBETA"}"#,
    ])
    #expect(generated.exitCode == 0)
    #expect(generated.names == ["Linux Swift 6.3"])
    #expect(generated.standardError.contains(label))
  }
}

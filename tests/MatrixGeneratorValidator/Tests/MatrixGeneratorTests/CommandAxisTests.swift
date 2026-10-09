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

/// Every job kind at once, each on one version, so a name is the bare form with
/// nothing fanned out.
private let everyKind = [
  "ENABLE_LINUX": "true",
  "ENABLE_MACOS": "true",
  "ENABLE_MACOS_SWIFTLY": "true",
  "ENABLE_WINDOWS": "true",
  "ENABLE_FREEBSD": "true",
  "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
  "ENABLE_ANDROID_SDK_BUILD": "true",
  "ENABLE_CXX_INTEROP": "true",
  "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
  "MACOS_SWIFT_VERSIONS": #"["6.3"]"#,
  "MACOS_XCODE_VERSIONS": #"["latest-beta"]"#,
  "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#,
  "LINUX_STATIC_SDK_VERSIONS": #"["6.3"]"#,
  "ANDROID_SDK_VERSIONS": #"["6.3"]"#,
  "ANDROID_NDK_VERSIONS": #"["r27d"]"#,
]

/// The names those kinds produce when each runs one command.
private let bareNames = [
  "Linux Swift 6.3",
  "macOS Xcode latest-beta",
  "macOS Swift 6.3",
  "macOS Swiftly main-snapshot (Xcode swift_6.3)",
  "Windows Swift 6.3",
  "Static Linux SDK Swift 6.3",
  "Android SDK Swift 6.3 NDK r27d",
  "Cxx interop Swift 6.3",
  "FreeBSD nightly-main - 14.3 - x86_64",
]

@Suite("The command axis")
struct CommandAxisTests {
  @Test("A map of label to command runs one job per label")
  func labeledCommands() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.2","6.3"]"#,
      "LINUX_COMMAND": """
        test: swift test
        release: swift test -c release
        """,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(
      generated.names == [
        "test Linux Swift 6.2", "test Linux Swift 6.3",
        "release Linux Swift 6.2", "release Linux Swift 6.3",
      ]
    )
    #expect(generated.entry(named: "test Linux Swift 6.3")?.command == "swift test")
    #expect(generated.entry(named: "release Linux Swift 6.3")?.command == "swift test -c release")
  }

  @Test("Every job kind takes a map of label to command")
  func everyKindTakesLabels() throws {
    // A kind reading only the scalar would drop every label but the value it read
    // as the whole command, leaving a job running something the caller did not ask
    // for under a name that says otherwise.
    var environment = everyKind
    environment["LINUX_COMMAND"] = "test: swift test\nbuild: swift build"
    environment["MACOS_COMMAND"] = "test: xcrun swift test\nbuild: xcrun swift build"
    environment["MACOS_SWIFTLY_COMMAND"] =
      "test: swiftly run swift test\nbuild: swiftly run swift build"
    environment["WINDOWS_COMMAND"] = "test: swift test\nbuild: swift build"
    environment["FREEBSD_COMMAND"] = "test: swift test\nbuild: swift build"
    environment["LINUX_STATIC_SDK_COMMAND"] = "test: swift build\nbuild: swift build --static-swift-stdlib"
    environment["ANDROID_SDK_COMMAND"] = "test: swift build\nbuild: swift build --target A"

    let generated = try Generator.run(environment)
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    // The kind whose command is the check itself takes no labels, so it keeps its
    // single entry.
    #expect(generated.count == 2 * 8 + 1, "got \(generated.names)")
    for name in bareNames where !name.hasPrefix("Cxx interop") {
      #expect(generated.names.contains("test \(name)"), "\(name) took no label")
      #expect(generated.names.contains("build \(name)"), "\(name) took no label")
    }
  }

  @Test("A label's own version list narrows it to those versions")
  func perLabelVersions() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.1","6.2","6.3"]"#,
      "LINUX_COMMAND": """
        test: swift test
        release:
          command: swift build -c release
          versions: ["6.3"]
        """,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(
      generated.names == [
        "test Linux Swift 6.1", "test Linux Swift 6.2", "test Linux Swift 6.3",
        "release Linux Swift 6.3",
      ]
    )
    #expect(generated.entry(named: "release Linux Swift 6.3")?.command == "swift build -c release")
  }

  @Test("A label's versions are read in the version list's order, not the label's")
  func perLabelVersionOrder() throws {
    // The order the entries come out in is the order a run is read, and it is the
    // version list that fixes it. Taking the label's order would reorder a run
    // because a caller wrote a label's versions the other way round.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.1","6.2","6.3"]"#,
      "LINUX_COMMAND": """
        release:
          command: swift build -c release
          versions: ["6.3", "6.1"]
        """,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.versions == ["6.1", "6.3"])
  }

  @Test("A macOS label selects from whichever of the two lists holds its versions")
  func perLabelVersionsAcrossTheMacOSLists() throws {
    // The Swift and Xcode lists combine, and a label's versions name one or the
    // other. Filtering both by the same names is what keeps a label naming an
    // Xcode version from producing a Swift entry for a toolchain that has no such
    // version.
    let generated = try Generator.run([
      "ENABLE_MACOS": "true",
      "MACOS_SWIFT_VERSIONS": #"["6.2","6.3"]"#,
      "MACOS_XCODE_VERSIONS": #"["latest-beta"]"#,
      "MACOS_COMMAND": """
        test: xcrun swift test
        beta:
          command: xcrun swift build
          versions: ["latest-beta"]
        """,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(
      generated.names == [
        "test macOS Xcode latest-beta", "beta macOS Xcode latest-beta",
        "test macOS Swift 6.2", "test macOS Swift 6.3",
      ]
    )
  }
}

@Suite("Job names under the command axis")
struct CommandNameStabilityTests {
  // Entry names become required status checks in adopting repositories, and two
  // swift-nio dev/ scripts parse them out of `gh pr checks`. The label is a suffix
  // like the OS and the architecture: it appears only once there is more than one
  // command to tell apart.

  @Test("One command leaves every job name alone, however it is written")
  func oneCommandDoesNotRenameJobs() throws {
    let scalar = try Generator.run(everyKind)
    #expect(scalar.exitCode == 0, "\(scalar.standardError)")
    #expect(scalar.names == bareNames)

    var labeled = everyKind
    labeled["LINUX_COMMAND"] = "test: swift test"
    labeled["MACOS_COMMAND"] = "test: xcrun swift test"
    labeled["MACOS_SWIFTLY_COMMAND"] = "test: swiftly run swift test"
    labeled["WINDOWS_COMMAND"] = "test: swift test"
    labeled["FREEBSD_COMMAND"] = "test: swift test"
    labeled["LINUX_STATIC_SDK_COMMAND"] = "test: swift build"
    labeled["ANDROID_SDK_COMMAND"] = "test: swift build"

    let single = try Generator.run(labeled)
    #expect(single.exitCode == 0, "\(single.standardError)")
    #expect(single.names == bareNames, "a single labeled command renamed a job")
    // Without this the names above would be stable because no label was read.
    #expect(single.entry(named: "Linux Swift 6.3")?.command == "swift test")
    #expect(single.entry(named: "Static Linux SDK Swift 6.3")?.command == "swift build")

    // A second command is what earns the suffix, so the bare names have to go.
    var two = everyKind
    two["LINUX_COMMAND"] = "test: swift test\nrelease: swift test -c release"
    let widened = try Generator.run(two)
    #expect(widened.exitCode == 0, "\(widened.standardError)")
    #expect(!widened.names.contains("Linux Swift 6.3"))
    #expect(widened.names.contains("test Linux Swift 6.3"))
    #expect(widened.names.contains("release Linux Swift 6.3"))
  }

  @Test("A job's name does not depend on another kind's command count")
  func namesDoNotDependOnAnotherKind() throws {
    // Each kind counts its own commands. Job names are the identity branch
    // protection matches on, so adding a Windows command must not rename a Linux
    // job.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "ENABLE_WINDOWS": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "WINDOWS_SWIFT_VERSIONS": #"["6.3"]"#,
      "WINDOWS_COMMAND": "test: swift test\nbuild: swift build",
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(
      generated.names == [
        "Linux Swift 6.3", "test Windows Swift 6.3", "build Windows Swift 6.3",
      ]
    )
  }

  @Test("The label sits after the OS and architecture suffixes")
  func labelIsTheLastSuffix() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_OS": #"["jammy","noble"]"#,
      "LINUX_HOST_ARCHS": #"["x86_64","aarch64"]"#,
      "LINUX_COMMAND": "test: swift test\nrelease: swift build -c release",
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.count == 8)
    #expect(generated.names.contains("test Linux Swift 6.3 jammy x86_64"))
    #expect(generated.names.contains("release Linux Swift 6.3 noble aarch64"))
    #expect(Set(generated.names).count == generated.count)
  }

  @Test("The label is parenthesized, so it cannot be read as part of the version")
  func labelIsParenthesized() throws {
    // `nightly-release` is a version and `release-build` is a label. Appended
    // bare, the two run together into a name whose words belong to different
    // axes, and a reader parsing a name out of `gh pr checks` has no way to tell
    // where the version ends.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["nightly-release"]"#,
      "LINUX_COMMAND": "debug-test: swift test\nrelease-build: swift build -c release",
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(
      generated.names == [
        "debug-test Linux Swift nightly-release",
        "release-build Linux Swift nightly-release",
      ]
    )
  }
}

@Suite("Telling a command from a map of commands")
struct CommandClassificationTests {
  @Test(
    "A command YAML reads as something else is still the command, byte for byte",
    arguments: [
      // A map whose key is everything before the colon.
      "swift test --filter Foo: Bar",
      #"echo "a: b""#,
      // Not YAML at all, so there is nothing to classify it by.
      "[ -f x ] && swift build",
      // A block scalar spanning lines is one command; a newline cannot be the
      // discriminator.
      "cd tests/TestPackage\nswift build",
      // A number and a comment, which a round-trip through YAML would rewrite.
      "swift build --scratch-path 24.10",
      "swift build # release",
    ]
  )
  func scalarCommandsAreUsedRaw(command: String) throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_COMMAND": command,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.names == ["Linux Swift 6.3"], "the command was read as a map of labels")
    #expect(generated.entries.first?.command == command)
  }

  @Test(
    "A malformed map of commands fails, naming the input and showing the value",
    arguments: [
      // A list has no labels to name the jobs with.
      ("[swift build, swift test]", "[swift build, swift test]"),
      ("test: swift test\nrelease:", "release: null"),
      ("test: swift test\nrelease: 5", "release: 5"),
      // A label with nothing to run leaves a job that reports success having done
      // nothing, under a name saying it ran the caller's command.
      ("test: swift test\nrelease: \"\"", #"release: """#),
      ("test:\n  command: \" \"", #"{"command":" "}"#),
      ("test: swift test\nrelease:\n  commnad: swift build", #"{"commnad":"swift build"}"#),
      ("test:\n  command: swift build\n  versions: []", #""versions":[]"#),
      ("test:\n  command: swift build\n  versions: \"6.3\"", #""versions":"6.3""#),
      ("test:\n  command: swift build\n  versions: [6.3]", #""versions":[6.3]"#),
    ]
  )
  func malformedCommandMapFails(command: String, reported: String) throws {
    // Each of these reads as no command for that label, so the job would run the
    // kind's default under a name saying it ran the caller's - or not appear at
    // all.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_COMMAND": command,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.count == 0)
    #expect(generated.standardError.contains("linux_command"))
    #expect(generated.standardError.contains(reported), "\(generated.standardError)")
  }

  @Test(
    "Every command input is checked",
    arguments: [
      ("LINUX_COMMAND", "linux_command", ["ENABLE_LINUX": "true"]),
      ("MACOS_COMMAND", "macos_command", ["ENABLE_MACOS": "true"]),
      ("MACOS_SWIFTLY_COMMAND", "macos_swiftly_command", ["ENABLE_MACOS_SWIFTLY": "true"]),
      ("WINDOWS_COMMAND", "windows_command", ["ENABLE_WINDOWS": "true"]),
      ("FREEBSD_COMMAND", "freebsd_command", ["ENABLE_FREEBSD": "true"]),
      (
        "LINUX_STATIC_SDK_COMMAND", "linux_static_sdk_command",
        ["ENABLE_LINUX_STATIC_SDK_BUILD": "true"]
      ),
      ("WASM_SDK_COMMAND", "wasm_sdk_command", ["ENABLE_WASM_SDK_BUILD": "true"]),
      (
        "EMBEDDED_WASM_SDK_COMMAND", "embedded_wasm_sdk_command",
        ["ENABLE_EMBEDDED_WASM_SDK_BUILD": "true"]
      ),
      ("ANDROID_SDK_COMMAND", "android_sdk_command", ["ENABLE_ANDROID_SDK_BUILD": "true"]),
    ]
  )
  func everyCommandInputIsChecked(key: String, name: String, enables: [String: String]) throws {
    var environment = enables
    environment[key] = "test: swift test\nrelease:"
    let generated = try Generator.run(environment)
    #expect(generated.exitCode != 0)
    #expect(generated.count == 0)
    #expect(generated.standardError.contains(name), "\(generated.standardError)")
  }

  @Test("A label written twice fails rather than running one of the two commands")
  func repeatedLabelFails() throws {
    // The parse keeps the last of a repeated key, so this reads as one command -
    // and one command earns no suffix, leaving the bare name on a job running the
    // second of the two.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_COMMAND": "test: swift test\ntest: swift build",
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.count == 0)
    #expect(generated.standardError.contains("linux_command"))
    #expect(generated.standardError.contains("more than once"), "\(generated.standardError)")
  }

  @Test("A label naming a version the kind does not run fails rather than doing nothing")
  func labelVersionsMustNameTheKindsVersions() throws {
    // The label selects from the kind's version list, so a name the list does not
    // hold produces no entry: the command is missing from a run that reports
    // success, which is how a version rename loses a job.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_COMMAND": """
        test: swift test
        release:
          command: swift build -c release
          versions: ["6.2"]
        """,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("linux_command"))
    #expect(generated.standardError.contains("release: 6.2"), "\(generated.standardError)")
  }

  @Test("The swiftly entries reject a label's versions rather than ignoring them")
  func swiftlyCommandTakesNoVersions() throws {
    // These fan out over macos_swiftly_toolchains, so there is no version list to
    // select from and the versions would carry nothing.
    let generated = try Generator.run([
      "ENABLE_MACOS_SWIFTLY": "true",
      "MACOS_SWIFTLY_COMMAND": """
        test:
          command: swiftly run swift test
          versions: ["6.3"]
        """,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.standardError.contains("macos_swiftly_command"))
    #expect(generated.standardError.contains("macos_swiftly_toolchains"))
  }

  @Test("A label's versions are not checked against a kind that is off")
  func versionsForDisabledKindDoNotFailTheRun() throws {
    // A kind that is off reads none of its commands, so a label naming a version
    // its list does not hold loses nothing. Failing there takes down the kinds
    // that are on over a setting nothing reads.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "WASM_SDK_COMMAND": """
        build:
          command: swift build --target NIOCore
          versions: ["6.9"]
        """,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.names == ["Linux Swift 6.3"])
  }
}

@Suite("A per-version command override and the command axis")
struct VersionOverrideCommandTests {
  @Test(
    "The override reaches every kind that runs the caller's own command",
    arguments: [
      ("ENABLE_LINUX", "LINUX_SWIFT_VERSIONS", "Linux Swift 6.3"),
      ("ENABLE_LINUX_STATIC_SDK_BUILD", "LINUX_STATIC_SDK_VERSIONS", "Static Linux SDK Swift 6.3"),
      ("ENABLE_WASM_SDK_BUILD", "WASM_SDK_VERSIONS", "Wasm SDK Swift 6.3"),
      (
        "ENABLE_EMBEDDED_WASM_SDK_BUILD", "EMBEDDED_WASM_SDK_VERSIONS",
        "Embedded Wasm SDK Swift 6.3"
      ),
      ("ENABLE_ANDROID_SDK_BUILD", "ANDROID_SDK_VERSIONS", "Android SDK Swift 6.3 NDK r27d"),
    ]
  )
  func overrideReplacesTheCallersCommand(
    enableKey: String,
    versionsKey: String,
    expectedName: String
  ) throws {
    // Every one of these honored `arguments:` already. A kind reading the base
    // command instead ran what the caller replaced, and still passed.
    var environment = [
      "ANDROID_NDK_VERSIONS": #"["r27d"]"#,
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_VERSION_OVERRIDES": #"{"6.3": {"command": "swift test --filter Foo"}}"#,
    ]
    environment[enableKey] = "true"
    environment[versionsKey] = #"["6.3"]"#

    let generated = try Generator.run(environment)
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.entry(named: expectedName)?.command == "swift test --filter Foo")
  }

  @Test("The override fails on a kind whose command is the check itself")
  func overrideFailsWhereTheCommandIsTheKind() throws {
    // Honoring it would leave a job named for a check it no longer runs; dropping
    // it silently is how a caller believes a command reached a job it did not.
    let generated = try Generator.run([
      "ENABLE_CXX_INTEROP": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_VERSION_OVERRIDES": #"{"6.3": {"command": "swift test --filter Foo"}}"#,
    ])
    #expect(generated.exitCode != 0)
    #expect(generated.count == 0)
    #expect(generated.standardError.contains("Cxx interop Swift"), "\(generated.standardError)")
    #expect(generated.standardError.contains("linux_version_overrides"))
  }

  @Test("Arguments still reach a kind whose command is the check itself")
  func argumentsStillReachEveryKind() throws {
    // Only `command:` is refused. A string override, which is the common case,
    // carries arguments and has to go on working.
    let generated = try Generator.run([
      "ENABLE_CXX_INTEROP": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_VERSION_OVERRIDES": #"{"6.3": "-Xswiftc -warnings-as-errors"}"#,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.count == 1)
    for entry in generated.entries {
      #expect(entry.commandArguments == ["-Xswiftc", "-warnings-as-errors"], "\(entry.name)")
    }
    #expect(
      generated.entry(named: "Cxx interop Swift 6.3")?.command
        == "${SCRIPTS_ROOT}/check-cxx-interop.sh"
    )
  }

  @Test("A version that kind does not run is not its business")
  func overrideOnAnotherVersionIsFine() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "ENABLE_CXX_INTEROP": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.2","6.3"]"#,
      "CXX_INTEROP_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_VERSION_OVERRIDES": #"{"6.2": {"command": "swift build"}}"#,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.entry(named: "Linux Swift 6.2")?.command == "swift build")
    #expect(generated.entry(named: "Linux Swift 6.3")?.command == "swift test")
    #expect(
      generated.entry(named: "Cxx interop Swift 6.3")?.command
        == "${SCRIPTS_ROOT}/check-cxx-interop.sh"
    )
  }

  @Test(
    "The override fails when more than one command is configured",
    arguments: [
      (
        "LINUX_COMMAND", "linux_command",
        ["ENABLE_LINUX": "true", "LINUX_SWIFT_VERSIONS": #"["6.3"]"#]
      ),
      (
        "LINUX_STATIC_SDK_COMMAND", "linux_static_sdk_command",
        [
          "ENABLE_LINUX_STATIC_SDK_BUILD": "true", "LINUX_STATIC_SDK_VERSIONS": #"["6.3"]"#,
          "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
        ]
      ),
    ]
  )
  func overrideNeedsOneCommandToReplace(
    key: String,
    reported: String,
    enables: [String: String]
  ) throws {
    // An override keyed on the version alone says nothing about which label it
    // replaces, so honoring it would give every label the same command and leave
    // jobs differing only in name. The message names the input the caller wrote,
    // which is the one to change.
    var environment = enables
    environment[key] = "test: swift test\nbuild: swift build"
    environment["LINUX_VERSION_OVERRIDES"] = #"{"6.3": {"command": "swift build"}}"#
    let generated = try Generator.run(environment)
    #expect(generated.exitCode != 0)
    #expect(generated.count == 0)
    #expect(generated.standardError.contains(reported), "\(generated.standardError)")
  }

  @Test("A version a kind does not run leaves that kind's labels alone")
  func overrideOnAnotherKindsVersionIsNotAmbiguous() throws {
    // The override names a version only the Linux tests run, so it reaches no SDK
    // build entry and there is nothing there for it to be ambiguous about.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.2","6.3"]"#,
      "LINUX_STATIC_SDK_VERSIONS": #"["6.3"]"#,
      "LINUX_STATIC_SDK_COMMAND": "test: swift build\nrelease: swift build -c release",
      "LINUX_VERSION_OVERRIDES": #"{"6.2": {"command": "swift build"}}"#,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(generated.entry(named: "Linux Swift 6.2")?.command == "swift build")
    #expect(generated.names.contains("test Static Linux SDK Swift 6.3"))
    #expect(generated.names.contains("release Static Linux SDK Swift 6.3"))
  }

  @Test("A version only another kind runs leaves the labeled tests alone")
  func overrideForAnotherKindDoesNotReachTheTests() throws {
    // The mirror of the case above: here the override reaches only the SDK build,
    // and the labeled Linux tests never run that version.
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "ENABLE_LINUX_STATIC_SDK_BUILD": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_STATIC_SDK_VERSIONS": #"["6.2"]"#,
      "LINUX_COMMAND": "test: swift test\nrelease: swift build -c release",
      "LINUX_VERSION_OVERRIDES": #"{"6.2": {"command": "swift build --static-swift-stdlib"}}"#,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    #expect(
      generated.entry(named: "Static Linux SDK Swift 6.2")?.command
        == "swift build --static-swift-stdlib"
    )
    #expect(generated.names.contains("test Linux Swift 6.3"))
    #expect(generated.names.contains("release Linux Swift 6.3"))
  }

  @Test("Arguments reach every label, since they are keyed on the version alone")
  func argumentsReachEveryLabel() throws {
    let generated = try Generator.run([
      "ENABLE_LINUX": "true",
      "LINUX_SWIFT_VERSIONS": #"["6.3"]"#,
      "LINUX_COMMAND": "test: swift test\nrelease: swift build -c release",
      "LINUX_VERSION_OVERRIDES": #"{"6.3": "-Xswiftc -warnings-as-errors"}"#,
    ])
    #expect(generated.exitCode == 0, "\(generated.standardError)")
    try #require(generated.count == 2)
    for entry in generated.entries {
      #expect(entry.commandArguments == ["-Xswiftc", "-warnings-as-errors"], "\(entry.name)")
    }
  }
}

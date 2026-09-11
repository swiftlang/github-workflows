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

// Entry names become required status checks in adopting repositories, and two
// swift-nio dev/ scripts parse them out of `gh pr checks`. A default version list
// decides which of those checks exist at all, so the sets below are pinned: a
// list edited in a workflow or in the generator has to be edited here too, where
// the diff says which jobs an adopter gains or loses.

/// A package whose minimum is the oldest version in the default lists, so nothing
/// is filtered and the pinned sets are the lists in full.
private let manifest = ["Package.swift": Generator.manifest(toolsVersion: "6.1")]

@Suite("Entry point defaults")
struct EntryPointDefaultTests {
  @Test(
    "A caller who passes nothing gets exactly these jobs",
    arguments: [
      (
        EntryPoint.packageTest,
        [
          "Linux Swift 6.1",
          "Linux Swift 6.2",
          "Linux Swift 6.3",
          "Linux Swift nightly-release",
          "Linux Swift nightly-main",
          "Windows Swift 6.1",
          "Windows Swift 6.2",
          "Windows Swift 6.3",
          "Windows Swift nightly-release",
          "Windows Swift nightly-main",
        ]
      ),
      (
        EntryPoint.toolchainMatrix,
        [
          "Linux Swift 6.1",
          "Linux Swift 6.2",
          "Linux Swift 6.3",
          "Linux Swift nightly-release",
          "Linux Swift nightly-main",
        ]
      ),
      (
        EntryPoint.benchmarks,
        [
          "Linux Swift 6.1",
          "Linux Swift 6.2",
          "Linux Swift 6.3",
          "Linux Swift nightly-release",
          "Linux Swift nightly-main",
        ]
      ),
    ]
  )
  func passNothingJobNames(entryPoint: EntryPoint, expected: [String]) throws {
    let generated = try Generator.run(try entryPoint.environment(), manifests: manifest)
    #expect(generated.exitCode == 0, "\(entryPoint): \(generated.standardError)")
    #expect(generated.names == expected, "\(entryPoint)")
  }

  @Test(
    "A caller who asks for macOS and nothing else gets the same jobs from every entry point"
  )
  func macOSJobNamesAgree() throws {
    let expected = ["macOS Swift 6.1", "macOS Swift 6.2", "macOS Swift 6.3"]
    for entryPoint in EntryPoint.all {
      var environment = try entryPoint.environment()
      environment["ENABLE_LINUX"] = "false"
      environment["ENABLE_WINDOWS"] = "false"
      environment["ENABLE_MACOS"] = "true"
      let generated = try Generator.run(environment, manifests: manifest)
      #expect(generated.exitCode == 0, "\(entryPoint): \(generated.standardError)")
      #expect(generated.names == expected, "\(entryPoint)")
    }
  }

  @Test("A caller who asks for the Android SDK build gets both NDK releases")
  func androidNDKJobNames() throws {
    var viaWorkflow = try EntryPoint.packageTest.environment()
    viaWorkflow["ENABLE_LINUX"] = "false"
    viaWorkflow["ENABLE_WINDOWS"] = "false"
    viaWorkflow["ENABLE_ANDROID_SDK_BUILD"] = "true"

    let expected = [
      "Android SDK Swift 6.3 NDK r27d",
      "Android SDK Swift nightly-release NDK r27d",
      "Android SDK Swift nightly-main NDK r27d",
      "Android SDK Swift 6.3 NDK r28c",
      "Android SDK Swift nightly-release NDK r28c",
      "Android SDK Swift nightly-main NDK r28c",
    ]

    let workflow = try Generator.run(viaWorkflow, manifests: manifest)
    #expect(workflow.exitCode == 0, "\(workflow.standardError)")
    #expect(workflow.names == expected)

    // An empty value is an absent one throughout the generator, so this is what a
    // caller reaching the script directly gets.
    var viaGenerator = viaWorkflow
    viaGenerator["ANDROID_NDK_VERSIONS"] = ""
    let generator = try Generator.run(viaGenerator, manifests: manifest)
    #expect(generator.exitCode == 0, "\(generator.standardError)")
    #expect(generator.names == expected)
  }
}

@Suite("Default agreement between the layers")
struct DefaultAgreementTests {
  /// Where a workflow's declared default deliberately differs from the
  /// generator's own, with why. Anything else differing is drift: the same input
  /// then means different things depending on which entry point a caller used.
  ///
  /// `enable_windows`: the generator defaults to the Linux-plus-Windows test
  /// sweep. `toolchain_matrix.yml` hands back a toolchain axis for a command
  /// execute_matrix.yml runs on every entry, which is usually a POSIX shell
  /// script.
  static let deliberateDifferences: [String: Set<String>] = [
    "package_test": [],
    "toolchain_matrix": ["ENABLE_WINDOWS"],
    "benchmarks": [],
  ]

  /// The entry point's environment with every job kind it forwards turned on, so
  /// no knob is dead when its default is compared.
  private func allKindsEnabled(_ entryPoint: EntryPoint) throws -> [String: String] {
    var environment = try entryPoint.environment()
    for enable in EntryPoint.jobKindEnables where environment[enable] != nil {
      environment[enable] = "true"
    }
    return environment
  }

  @Test(
    "A workflow's declared default matches the generator's own",
    arguments: EntryPoint.all
  )
  func declaredDefaultsMatchTheGenerator(entryPoint: EntryPoint) throws {
    let baseline = try allKindsEnabled(entryPoint)
    let documented = try #require(Self.deliberateDifferences[entryPoint.workflow])

    // Emptying a variable is how the generator is asked for its own default, so
    // the two runs differ only where the two layers disagree. The enables are
    // held at "true" in both: emptying one would take its whole block away and
    // say nothing about the defaults inside it.
    var askingTheGenerator = baseline
    for key in try entryPoint.inputBackedKeys()
    where !EntryPoint.jobKindEnables.contains(key) && !documented.contains(key) {
      askingTheGenerator[key] = ""
    }
    #expect(askingTheGenerator != baseline, "\(entryPoint) forwards no input to compare")

    let fromWorkflow = try Generator.run(baseline, manifests: manifest)
    let fromGenerator = try Generator.run(askingTheGenerator, manifests: manifest)
    #expect(fromWorkflow.exitCode == 0, "\(entryPoint): \(fromWorkflow.standardError)")
    #expect(fromGenerator.exitCode == 0, "\(entryPoint): \(fromGenerator.standardError)")
    #expect(!fromWorkflow.entries.isEmpty, "\(entryPoint) generated nothing to compare")
    #expect(fromWorkflow.names == fromGenerator.names, "\(entryPoint)")
  }

  @Test(
    "No entry point carries its own copy of the macOS release list",
    arguments: EntryPoint.all
  )
  func macOSListHasOneSource(entryPoint: EntryPoint) throws {
    // Empty means the generator's own list of release versions. A workflow
    // spelling that list out instead states a default that agrees until one of
    // the two copies is edited, and the macOS list has no nightly to fan out
    // over, so no entry point has a reason of its own to name versions.
    let declared = try #require(
      try entryPoint.environment()["MACOS_SWIFT_VERSIONS"],
      "\(entryPoint) no longer forwards the macOS version list"
    )
    #expect(declared == "", "\(entryPoint)")
  }

  @Test("Windows is off by default outside the test sweep, and one input away")
  func windowsIsOffByDefault() throws {
    let entryPoint = EntryPoint.toolchainMatrix
    let environment = try entryPoint.environment()
    #expect(environment["ENABLE_WINDOWS"] == "false", "\(entryPoint)")

    let off = try Generator.run(environment, manifests: manifest)
    #expect(off.exitCode == 0, "\(entryPoint): \(off.standardError)")
    #expect(!off.platforms.contains("Windows"), "\(entryPoint)")

    var on = environment
    on["ENABLE_WINDOWS"] = "true"
    let gained = try Generator.run(on, manifests: manifest)
    #expect(gained.exitCode == 0, "\(entryPoint): \(gained.standardError)")
    #expect(
      Set(gained.names).subtracting(off.names) == [
        "Windows Swift 6.1",
        "Windows Swift 6.2",
        "Windows Swift 6.3",
        "Windows Swift nightly-release",
        "Windows Swift nightly-main",
      ],
      "\(entryPoint)"
    )
  }
}

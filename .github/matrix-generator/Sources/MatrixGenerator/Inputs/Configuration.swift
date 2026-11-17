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

/// What the run was configured with, as the caller wrote it.
struct Configuration {
  /// The releases a platform tests by default, oldest first, named relative to the current
  /// release so that a job's name, which is a required status check, survives a new release.
  static let releaseLabels = ["current-2", "current-1", "current"]
  /// The nightlies every platform runs: the next release's branch, and main.
  static let nightlies = ["nightly-release", "nightly-main"]
  /// The Swift versions a platform runs by default: every release, plus both nightlies.
  static let defaultVersions = releaseLabels + nightlies
  /// The Swift versions an SDK build runs by default. An SDK ships from the release it was
  /// cut for onward, so an older release would build against one never published for it.
  static let defaultSDKVersions = ["current"] + nightlies

  @Input("ENABLE_LINUX") var linuxEnabled = true
  @Input("ENABLE_MACOS") var macOSEnabled = true
  @Input("ENABLE_MACOS_SWIFTLY") var swiftlyEnabled = true
  @Input("ENABLE_WINDOWS") var windowsEnabled = true
  @Input("ENABLE_FREEBSD") var freeBSDEnabled = true
  @Input("ENABLE_CXX_INTEROP") var cxxInteropEnabled = true

  /// The release `current` names, such as `6.4`. The workflow supplies it, so that a pinned
  /// workflow version keeps the versions it was released with.
  @Input("SWIFT_CURRENT_RELEASE") var currentRelease = ""
  /// The branch spelling `nightly-release` names, such as `6.4.x`.
  @Input("SWIFT_NIGHTLY_RELEASE") var nightlyBranch = ""
  @Input("SWIFT_FLAGS") var swiftFlags = ""
  @Input("SWIFT_NIGHTLY_FLAGS") var swiftNightlyFlags = ""
  @Input("MINIMUM_SWIFT_VERSION") var minimumSwiftVersion = ""
  @Input("PACKAGE_PATH") var packagePath = ""
  @Input("ENABLE_SUBDIRECTORY_MANIFEST_SEARCH") var searchSubdirectories = false
  @Input("MATRIX_MODE") var matrixMode = "jobs"
  @Input("MATRIX_FORMAT") var matrixFormat = "yaml"

  @Input("LINUX_SWIFT_VERSIONS") var linuxVersions = Configuration.defaultVersions
  @Input("LINUX_OS") var linuxOS = OSList(Runner.ubuntuDistribution)
  @Input("LINUX_HOST_ARCHS") var linuxArchitectures = ["x86_64"]
  @Input("LINUX_COMMAND") var linuxCommands: Commands = "swift test"
  @Input("LINUX_SETUP_COMMAND") var linuxSetupCommand = ""
  @Input("LINUX_ENV_VARS") var linuxEnvironment = JSONValue.object([:])
  @Input("LINUX_VERSION_OVERRIDES") var linuxOverrides = VersionOverrides()
  @Input("LINUX_USE_DOCKER") var linuxUsesDocker = false
  @Input("LINUX_DOCKERFILE") var linuxDockerfile = ""
  @Input("LINUX_DOCKER_CAPABILITIES") var linuxCapabilities: [String] = []
  @Input("LINUX_DOCKER_SECURITY_OPTIONS") var linuxSecurityOptions: [String] = []

  @Input("MACOS_XCODE_VERSIONS") var macOSXcodeVersions: [String] = []
  @Input("MACOS_SWIFT_VERSIONS") var macOSVersions: [String] = []
  @Input("MACOS_OS") var macOSOS: OSList = "goldengate"
  @Input("MACOS_ARCH") var macOSArchitecture = "ARM64"
  @Input("MACOS_RUNNER_POOL") var macOSPool = ""
  @Input("MACOS_COMMAND") var macOSCommands: Commands = "xcrun swift test"
  @Input("MACOS_SETUP_COMMAND") var macOSSetupCommand = ""
  @Input("MACOS_ENV_VARS") var macOSEnvironment = JSONValue.object([:])
  @Input("MACOS_VERSION_OVERRIDES") var macOSOverrides = VersionOverrides()
  @Input("XCODE_SCHEME") var xcodeScheme = ""
  @Input("XCODE_TARGETS") var xcodeTargets = ""
  @Input("XCODE_DEBUG_OUTPUT") var xcodeDebugOutput = false
  @Input("MACOS_SWIFTLY_TOOLCHAINS") var swiftlyToolchains: [SwiftlyToolchain] = []
  @Input("MACOS_SWIFTLY_COMMAND") var swiftlyCommands: Commands = "swiftly run swift test"

  @Input("WINDOWS_SWIFT_VERSIONS") var windowsVersions = Configuration.defaultVersions
  @Input("WINDOWS_OS") var windowsOS: OSList = "windows-2022"
  @Input("WINDOWS_COMMAND") var windowsCommands: Commands = "swift test"
  @Input("WINDOWS_SETUP_COMMAND") var windowsSetupCommand = ""
  @Input("WINDOWS_ENV_VARS") var windowsEnvironment = JSONValue.object([:])
  @Input("WINDOWS_VERSION_OVERRIDES") var windowsOverrides = VersionOverrides()
  @Input("WINDOWS_USE_DOCKER") var windowsUsesDocker = false
  /// Minutes for a Windows job, which installs a toolchain and the Visual Studio Build Tools
  /// before building. Zero leaves the executor's timeout.
  @Input("WINDOWS_JOB_TIMEOUT") var windowsTimeoutMinutes = 0

  @Input("ANDROID_NDK_VERSIONS") var androidNDKVersions = ["r30"]
  /// The triples that are built (not executed).
  @Input("ANDROID_SDK_BUILD_TRIPLES") var androidBuildTriples = ["aarch64-unknown-linux-android28"]
  /// The triples that are built and then run on an emulator. The emulator's architecture must be
  /// one the runner can accelerate, which is the runner's own.
  @Input("ANDROID_EMULATOR_TEST_TRIPLES") var androidEmulatorTestTriples = ["x86_64-unknown-linux-android28"]

  @Input("CXX_INTEROP_SWIFT_VERSIONS") var cxxInteropVersions: [String] = []

  @Input("FREEBSD_SWIFT_VERSIONS") var freeBSDVersions = ["nightly-main"]
  @Input("FREEBSD_OS_VERSIONS") var freeBSDOSVersions = ["14.3"]
  @Input("FREEBSD_COMMAND") var freeBSDCommands: Commands = "swift test"
  /// Minutes for a FreeBSD job, which boots a virtual machine and installs a toolchain into it
  /// before building. Zero leaves the executor's timeout.
  @Input("FREEBSD_JOB_TIMEOUT") var freeBSDTimeoutMinutes = 0
  @Input("FREEBSD_SETUP_COMMAND") var freeBSDSetupCommand = ""
  @Input("FREEBSD_ENV_VARS") var freeBSDEnvironmentVariables = ""

  /// The Swift SDK builds, which differ only in the prefix their inputs share, the SDK they
  /// build against, and the name their jobs carry.
  let sdkBuilds = [
    SDKBuild(prefix: "linux_static_sdk", kind: .staticLinux, name: "Static Linux SDK Swift"),
    SDKBuild(prefix: "wasm_sdk", kind: .wasm, name: "Wasm SDK Swift"),
    SDKBuild(prefix: "embedded_wasm_sdk", kind: .embeddedWasm, name: "Embedded Wasm SDK Swift"),
    SDKBuild(prefix: "android_sdk", kind: .android, name: "Android SDK Swift"),
  ]

  /// Every per-version overrides input, so that an input no enabled group reads is still
  /// reported.
  var allOverrides: [VersionOverrides] {
    [self.linuxOverrides, self.macOSOverrides, self.windowsOverrides] + self.sdkBuilds.map(\.overrides)
  }

  /// The Android SDK build.
  var androidSDKBuild: SDKBuild {
    guard let build = self.sdkBuilds.first(where: { $0.kind == .android }) else {
      fatal("no Android SDK build is configured.")
    }
    return build
  }
}

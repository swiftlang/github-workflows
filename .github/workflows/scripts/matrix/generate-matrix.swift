#!/usr/bin/env swift
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

// Generates the job matrix the rest of the workflow runs: the workflow's inputs in
// as environment variables, the matrix out on standard output. Executable, so the
// workflows invoke it by path.
//
// yq reads the YAML an input is written in and writes the YAML the matrix comes out
// as, and jq writes the JSON form. Everything between them is typed.

import Foundation

// MARK: - Configuration

/// What the run was configured with, as the caller wrote it.
struct Configuration {
    /// The releases a platform tests by default, oldest first.
    static let releases = ["6.1", "6.2", "6.3"]
    /// The nightlies every platform runs: the next release's branch, and main.
    static let nightlies = ["nightly-release", "nightly-main"]
    /// The most recent release, which the SDK builds run on rather than every version:
    /// bumping a release means adding to `releases` and nothing else.
    static var latestRelease: String {
        guard let latest = releases.last else {
            fatal("Configuration.releases is empty, so no release is left for the supplementary checks to run on.")
        }
        return latest
    }
    /// The Swift versions a platform runs by default: every release, plus both nightlies.
    static let defaultVersions = releases + nightlies
    /// The Swift versions an SDK build runs by default. An SDK ships from the release it was
    /// cut for onward, so an older release would build against one never published for it.
    static let defaultSDKVersions = [latestRelease] + nightlies

    @Input("ENABLE_LINUX") var linuxEnabled = true
    @Input("ENABLE_MACOS") var macOSEnabled = false
    @Input("ENABLE_MACOS_SWIFTLY") var swiftlyEnabled = false
    @Input("ENABLE_WINDOWS") var windowsEnabled = true
    @Input("ENABLE_FREEBSD") var freeBSDEnabled = false
    @Input("ENABLE_ANDROID_EMULATOR_TESTS") var androidEmulatorEnabled = false
    @Input("ENABLE_CXX_INTEROP") var cxxInteropEnabled = false

    @Input("NIGHTLY_RELEASE_TOKEN") var nightlyReleaseToken = "6.4.x"
    @Input("SWIFT_FLAGS") var swiftFlags = ""
    @Input("SWIFT_NIGHTLY_FLAGS") var swiftNightlyFlags = ""
    @Input("MINIMUM_SWIFT_VERSION") var minimumSwiftVersion = ""
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
    @Input("MACOS_OS") var macOSOS: OSList = "tahoe"
    @Input("MACOS_ARCH") var macOSArchitecture = "ARM64"
    @Input("MACOS_RUNNER_POOL") var macOSPool = "general"
    @Input("MACOS_COMMAND") var macOSCommands: Commands = "xcrun swift test"
    @Input("MACOS_SETUP_COMMAND") var macOSSetupCommand = ""
    @Input("MACOS_ENV_VARS") var macOSEnvironment = JSONValue.object([:])
    @Input("MACOS_VERSION_OVERRIDES") var macOSOverrides = VersionOverrides()
    /// The owner whose self-hosted macOS pools these entries need. Empty means no check.
    @Input("MACOS_REPOSITORY_OWNER") var macOSRepositoryOwner = ""
    @Input("GITHUB_REPOSITORY_OWNER") var repositoryOwner = ""
    @Input("XCODE_SCHEME") var xcodeScheme = ""
    @Input("XCODE_TARGETS") var xcodeTargets = ""
    @Input("XCODE_DEBUG_OUTPUT") var xcodeDebugOutput = false
    @Input("MACOS_SWIFTLY_TOOLCHAINS") var swiftlyToolchains = [
        SwiftlyToolchain(xcodeVersion: "swift_6.3", swiftlyToolchain: "main-snapshot")
    ]
    @Input("MACOS_SWIFTLY_COMMAND") var swiftlyCommands: Commands = "swiftly run swift test"

    @Input("WINDOWS_SWIFT_VERSIONS") var windowsVersions = Configuration.defaultVersions
    @Input("WINDOWS_OS") var windowsOS: OSList = "windows-2022"
    @Input("WINDOWS_COMMAND") var windowsCommands: Commands = "swift test"
    @Input("WINDOWS_SETUP_COMMAND") var windowsSetupCommand = ""
    @Input("WINDOWS_ENV_VARS") var windowsEnvironment = JSONValue.object([:])
    @Input("WINDOWS_VERSION_OVERRIDES") var windowsOverrides = VersionOverrides()
    @Input("WINDOWS_USE_DOCKER") var windowsUsesDocker = false

    @Input("ANDROID_NDK_VERSIONS") var androidNDKVersions = ["r27d", "r28c"]
    @Input("ANDROID_SDK_TRIPLES") var androidTriples = [
        "aarch64-unknown-linux-android28", "x86_64-unknown-linux-android28",
    ]

    @Input("CXX_INTEROP_SWIFT_VERSIONS") var cxxInteropVersions: [String] = []

    @Input("FREEBSD_SWIFT_VERSIONS") var freeBSDVersions = ["nightly-main"]
    @Input("FREEBSD_OS_VERSIONS") var freeBSDOSVersions = ["14.3"]
    @Input("FREEBSD_COMMAND") var freeBSDCommands: Commands = "swift test"
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
    var allOverrides: [VersionOverrides] { [self.linuxOverrides, self.macOSOverrides, self.windowsOverrides] }

    /// The Android SDK build, whose output the emulator tests run.
    var androidSDKBuild: SDKBuild {
        guard let build = self.sdkBuilds.first(where: { $0.kind == .android }) else {
            fatal("no Android SDK build is configured, so nothing produces what the emulator runs.")
        }
        return build
    }
}

// MARK: - What the configuration asks for

extension Configuration {
    /// Fails on a pair of inputs that cannot both be honored. Each would otherwise produce a
    /// matrix without the jobs the caller asked for.
    func validatePairings(in mode: Matrix.Mode) {
        // Toolchains mode emits neither the emulator nor the build it runs, so the pairing only
        // has to hold where both could appear.
        if mode == .jobs && self.androidEmulatorEnabled && !self.androidSDKBuild.enabled {
            fatal(
                "enable_android_emulator_tests needs enable_android_sdk_build; the emulator runs what that build produces."
            )
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

    /// The Swift versions the macOS entries run.
    ///
    /// The two macOS lists are different ways of naming a toolchain, not competing spellings
    /// of one, so they combine; the release list is the default only when neither is set.
    var macOSSwiftVersions: [String] {
        if self.macOSVersions.isEmpty && self.macOSXcodeVersions.isEmpty {
            return Configuration.releases
        }
        return self.macOSVersions
    }

    /// The Swift versions the Cxx interop check runs.
    ///
    /// The check is supplementary rather than a full compatibility check, so it runs on the
    /// newest release in the Linux list unless a caller names more.
    var cxxInteropSwiftVersions: [String] {
        if self.cxxInteropVersions.isEmpty {
            return [SwiftVersion.newestRelease(in: self.linuxVersions)]
        }
        return self.cxxInteropVersions
    }

    /// Whether the macOS entries are withheld from this repository, saying so when they are.
    ///
    /// They run on self-hosted pools a fork cannot reach, where its jobs would queue until they
    /// time out. Withholding them produces no jobs rather than jobs that cannot start, and the
    /// checks then treat macOS as a group this repository did not ask for.
    func withholdsMacOS() -> Bool {
        let owner = self.macOSRepositoryOwner
        if owner.isEmpty || self.repositoryOwner.isEmpty || owner == self.repositoryOwner {
            return false
        }
        log("Skipping macOS entries: this repository's owner (\(self.repositoryOwner)) is not \(owner)")
        return true
    }

    /// The flags an entry's command runs with, and what a version's override adds to them.
    func flags(with overrides: VersionOverrides = VersionOverrides()) -> SwiftFlags {
        SwiftFlags(release: self.swiftFlags, nightly: self.swiftNightlyFlags, overrides: overrides)
    }
}

// MARK: - Generating

struct Generator {
    private let configuration: Configuration
    private let mode: Matrix.Mode

    /// Derived once when the run starts rather than at each point one is read: deriving one
    /// logs what it resolved to, and reading it twice would log it twice.
    private let linuxImages: [ContainerImage?]
    private let minimum: MinimumVersion
    private let macOSIsWithheld: Bool
    /// Derived before the owner check, so a fork - which gets no macOS entries at all - still
    /// reports a target the caller got wrong.
    private let xcodeTargets: [XcodeTarget]

    /// Everything else a group needs is read from the configuration as that group is built.
    init(_ configuration: Configuration, mode: Matrix.Mode) {
        self.configuration = configuration
        self.mode = mode
        self.linuxImages = configuration.linuxImages()
        self.minimum = MinimumVersion(for: configuration)
        self.xcodeTargets = XcodeTarget.list(in: configuration)
        self.macOSIsWithheld = configuration.withholdsMacOS()
    }
}

// MARK: - Assembling the job groups

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
            releaseToken: self.configuration.nightlyReleaseToken,
            flags: self.configuration.flags(with: self.configuration.linuxOverrides),
            setupCommand: self.configuration.linuxSetupCommand,
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
            flags: self.configuration.flags(with: self.configuration.macOSOverrides),
            setupCommand: self.configuration.macOSSetupCommand,
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
            setupCommand: self.configuration.macOSSetupCommand,
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
            releaseToken: self.configuration.nightlyReleaseToken,
            flags: self.configuration.flags(with: self.configuration.windowsOverrides),
            setupCommand: self.configuration.windowsSetupCommand,
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
                overrides: self.configuration.linuxOverrides,
                namePrefix: "Cxx interop Swift"
            ),
            platform: .linux,
            minimum: self.minimum,
            releaseToken: self.configuration.nightlyReleaseToken,
            flags: self.configuration.flags(with: self.configuration.linuxOverrides),
            setupCommand: self.configuration.linuxSetupCommand,
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
            setupCommand: self.configuration.freeBSDSetupCommand,
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
        var jobs = SwiftBuildJobs(
            settings: JobGroupSettings(
                enableInput: build.enableInput,
                versionAxis: .list(input: build.versionsInput),
                versions: build.versions,
                commandSource: .input(name: build.commandInput),
                commands: build.commands,
                overrides: self.configuration.linuxOverrides,
                namePrefix: build.name
            ),
            platform: .linux,
            minimum: self.minimum,
            releaseToken: self.configuration.nightlyReleaseToken,
            flags: self.configuration.flags(with: self.configuration.linuxOverrides),
            setupCommand: build.setupCommand,
            environment: self.configuration.linuxEnvironment,
            runners: [self.configuration.primaryLinuxRunner],
            sdk: MatrixEntry.SwiftBuild.SDK(kind: build.kind)
        )
        guard build.kind == .android else { return jobs }
        jobs.sdk?.triples = self.configuration.androidTriples
        jobs.ndkVersions = self.configuration.androidNDKVersions
        jobs.androidEmulator = self.configuration.androidEmulatorEnabled
        // The emulator runs what the build produced, so the build is told to make test binaries
        // and takes none of the flags inputs.
        jobs.flags = .always(self.configuration.androidEmulatorEnabled ? "--build-tests" : "")
        return jobs
    }

    /// The groups this run produces entries for, in the order the jobs come out in.
    ///
    /// A group nobody asked for is not built, so nothing it carries is read and nothing it
    /// carries can fail the run. This is the only place that decides whether a group is built.
    private var jobGroups: [any JobGroup] {
        var groups: [any JobGroup] = []
        if self.configuration.linuxEnabled { groups.append(self.linuxJobs) }
        // The macOS pools are self-hosted, and a fork cannot reach them.
        if self.configuration.macOSEnabled && !self.macOSIsWithheld { groups.append(self.macOSJobs) }
        if self.configuration.swiftlyEnabled && !self.macOSIsWithheld { groups.append(self.macOSSwiftlyJobs) }
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

// MARK: - Producing the matrix

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
        // still reports success, whatever the other groups produced. A deliberate skip - the
        // fork guard, or toolchains mode - leaves the group unbuilt, so it is not such a group.
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
            entries += produced
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

// MARK: - Xcodebuild targets

/// A platform built and tested through xcodebuild. It is a step inside a macOS job rather
/// than a job of its own.
struct XcodeTarget: Encodable {
    var platform: String
    var scheme: String
    var buildDestination: String
    var testDestination: String
    var build: Bool
    var test: Bool

    enum CodingKeys: String, CodingKey {
        case platform, scheme, build, test
        case buildDestination = "build_destination"
        case testDestination = "test_destination"
    }

    /// The destinations a target takes when it names none of its own.
    ///
    /// These name the newest device of each kind, which ages with every Xcode release, so a
    /// target can give its own instead.
    static let destinations: [String: (build: String, test: String)] = [
        "macOS": (build: "generic/platform=macos,variant=macos", test: "name=My Mac,variant=macos"),
        "Catalyst": (
            build: "generic/platform=macos,variant=Mac Catalyst", test: "name=My Mac,variant=Mac Catalyst"
        ),
        "iOS": (build: "generic/platform=ios", test: "name=iPhone Air"),
        "watchOS": (build: "generic/platform=watchos", test: "name=Apple Watch Ultra 3 (49mm)"),
        "tvOS": (build: "generic/platform=tvos", test: "name=Apple TV 4K (3rd generation)"),
        "visionOS": (build: "generic/platform=visionos", test: "name=Apple Vision Pro"),
    ]
}

extension XcodeTarget {
    /// The platforms to build and test through xcodebuild, carried by every macOS entry: a map
    /// of platform to that target's settings, or a list of platforms taking the defaults.
    ///
    /// Reading them runs yq over what the caller wrote.
    static func list(in configuration: Configuration) -> [XcodeTarget] {
        let text = configuration.xcodeTargets
        if text.isEmpty { return [] }
        // A scalar is rejected rather than read as one platform: the parse is here only to tell a
        // map from a list, and the keys it yields have to match one in `destinations`, so YAML
        // rewriting one cannot pass unnoticed.
        guard let parsed = Parsed(text) else {
            fatal("xcode_targets is not valid JSON or YAML: \(text)")
        }
        guard parsed.isCollection else {
            fatal(
                """
                xcode_targets takes a map, such as {iOS: {build: true}}, or a list, such as [iOS, watchOS], \
                but got: \(text)
                """
            )
        }

        // A list asks for each platform with every setting left at its default.
        var members = parsed.mapMembers.map { (platform: $0.key, settings: $0.value) }
        if let listed = parsed.value.asArray {
            guard listed.allSatisfy({ $0.asString != nil }) else {
                fatal("xcode_targets as a list takes platform names, such as [iOS, watchOS], but got: \(text)")
            }
            members = listed.map { (platform: $0.text, settings: JSONValue.object([:])) }
        }

        return members.map { platform, value in
            guard let defaults = XcodeTarget.destinations[platform] else {
                fatal(
                    """
                    xcode_targets names an unknown platform '\(platform)'; the platforms are macOS, Catalyst, iOS, \
                    watchOS, tvOS and visionOS.
                    """
                )
            }
            // A platform named with no settings is written `iOS:`, which parses as null.
            guard case .object(let settings) = (value.isNull ? .object([:]) : value) else {
                fatal(
                    "xcode_targets settings for \(platform) take the form {build: true, test: true}, but got: \(value)"
                )
            }
            // A misspelled setting would otherwise be dropped and its default left in place: a
            // target carrying `sheme` would build the default scheme, or fail for lack of one.
            let unknown = Set(settings.keys)
                .subtracting(["build", "test", "scheme", "build_destination", "test_destination"]).sorted()
            guard unknown.isEmpty else {
                fatal(
                    """
                    xcode_targets settings for \(platform) include unknown keys: \(unknown.joined(separator: ", ")). \
                    A target takes build, test, scheme, build_destination and test_destination.
                    """
                )
            }

            func flag(_ key: String, or fallback: Bool) -> Bool {
                guard let setting = settings[key]?.nonNull else { return fallback }
                guard let value = setting.asBool else {
                    fatal(
                        "xcode_targets settings for \(platform) take build and test as true or false, but got: \(value)"
                    )
                }
                return value
            }
            // Building is the default because a package can be built for every platform, while
            // testing needs a simulator and takes far longer.
            let build = flag("build", or: true)
            let test = flag("test", or: false)
            guard build || test else {
                fatal(
                    "xcode_targets asks for \(platform) with build and test both false, so the target would do nothing."
                )
            }

            let scheme = settings["scheme"]?.text ?? configuration.xcodeScheme
            if scheme.isEmpty {
                fatal(
                    """
                    xcode_targets names \(platform) but no scheme reaches it; set xcode_scheme, or give the target \
                    its own. xcodebuild builds nothing without a scheme.
                    """
                )
            }
            return XcodeTarget(
                platform: platform,
                scheme: scheme,
                buildDestination: settings["build_destination"]?.text ?? defaults.build,
                testDestination: settings["test_destination"]?.text ?? defaults.test,
                build: build,
                test: test
            )
        }
    }
}

// MARK: - Job groups

/// One group of jobs the matrix can hold: the entries one enable turns on.
protocol JobGroup {
    var settings: JobGroupSettings { get }
    /// In the order the jobs come out in.
    var entries: [MatrixEntry] { get }
    /// Fails on a configuration that would drop a job the caller asked for from this group.
    func validate(against minimum: MinimumVersion)
}

extension JobGroup {
    /// The checks every group makes.
    func validateSettings(against minimum: MinimumVersion) {
        self.settings.validateCommandVersions()
        self.settings.validateReplaceableCommand()
        self.settings.validateRunnableVersions(minimum)
    }

    func validate(against minimum: MinimumVersion) {
        self.validateSettings(against: minimum)
    }
}

/// What a job group fans out over.
enum VersionAxis {
    /// A Swift version list, named by this input.
    case list(input: String)
    /// Swiftly-managed toolchains rather than a version list, named by this input, so a label
    /// has no versions to select from.
    case toolchains(input: String)

    /// The input a message names, so the caller knows which knob to turn.
    var inputName: String {
        switch self {
        case .list(let input): return input
        case .toolchains(let input): return input
        }
    }
}

/// Where a job group's command comes from.
enum CommandSource {
    /// The caller names it, in the input given, so a per-version `command:` override can replace
    /// it.
    case input(name: String)
    /// The command is the check itself rather than a place to run one, so an override replacing
    /// it would leave the job named for something it no longer does.
    case fixed

    /// The input a message names, or nil when the command is the check itself.
    var inputName: String? {
        switch self {
        case .input(let name): return name
        case .fixed: return nil
        }
    }
}

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
            if self.commands.contains(where: { $0.swiftVersions != nil }) {
                fatal("\(commandsInput) takes no versions; its toolchains come from \(toolchainsInput).")
            }
        case .list:
            let selectable = self.selectableVersions
            let unmatched = self.commands.flatMap { variant in
                (variant.swiftVersions ?? []).filter { !selectable.contains($0) }.map { "\(variant.label): \($0)" }
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
            guard let swiftVersions = variant.swiftVersions else { continue }
            guard variant.versions(among: self.versionsExemptFromMinimum + runnable).isEmpty else { continue }
            fatal(
                """
                \(commandsInput) label '\(variant.label)' runs only on \(swiftVersions.joined(separator: " ")), which \
                minimum Swift version \(minimum.text) removes, so that label would produce no jobs while the others \
                still run. \(MinimumVersion.remedy)
                """
            )
        }
    }
}

// MARK: - Where a job runs

/// A machine an entry runs on: the labels that select it, and what it contributes to an
/// entry's name when its group runs on more than one.
struct Runner {
    /// The distribution GitHub's Ubuntu runners run, which is what `linux_os` defaults to: a
    /// job on any other one needs a container image.
    static let ubuntuDistribution = "noble"

    var labels: [String]
    var name: String

    /// The GitHub Ubuntu runner for an architecture.
    static func ubuntu(architecture: String) -> Runner {
        Runner(labels: [architecture == "aarch64" ? "ubuntu-24.04-arm" : "ubuntu-24.04"], name: architecture)
    }

    /// A Windows runner, which the label that selects it also names.
    static func windows(label: String) -> Runner {
        Runner(labels: [label], name: label)
    }

    /// A machine from one of the self-hosted macOS pools.
    static func macOS(os: String, architecture: String, pool: String) -> Runner {
        Runner(labels: ["self-hosted", "macos", os, architecture, pool], name: os)
    }
}

/// The self-hosted macOS machines a group's entries run on.
struct MacOSMachines {
    var operatingSystems: [String]
    var architecture: String
    var pool: String

    /// The machines the entries fan out over.
    var runners: [Runner] {
        self.operatingSystems.map { Runner.macOS(os: $0, architecture: self.architecture, pool: self.pool) }
    }

    /// The machines one swiftly toolchain runs on: an entry naming its own OS runs there alone,
    /// and on the architecture it names.
    func runners(for toolchain: SwiftlyToolchain) -> [Runner] {
        let operatingSystems = toolchain.osVersion.map { [$0] } ?? self.operatingSystems
        return operatingSystems.map {
            Runner.macOS(os: $0, architecture: toolchain.architecture ?? self.architecture, pool: self.pool)
        }
    }
}

/// A Swift container image an entry runs in, and what the Docker inputs add to it.
struct ContainerImage {
    /// The only Windows runner a Swift container image is published for.
    static let windowsRunner = "windows-2022"

    /// The Swift Windows Server image, which is tagged like a distribution.
    static let windows = ContainerImage(distribution: "windowsservercore-ltsc2022")

    /// The part of the image tag that follows the toolchain, such as `noble`.
    var distribution: String
    /// A Dockerfile that extends the image, when the caller named one.
    var dockerfile: String?
    var capabilities: [String]?
    var securityOptions: [String]?

    /// The image one toolchain runs in.
    func container(_ toolchain: Toolchain) -> MatrixEntry.SwiftBuild.Container {
        MatrixEntry.SwiftBuild.Container(
            image: toolchain.image(distribution: self.distribution),
            dockerfile: self.dockerfile,
            capabilities: self.capabilities,
            securityOptions: self.securityOptions
        )
    }
}

/// The flags an entry's command runs with, by the kind of toolchain it runs on.
struct SwiftFlags {
    /// What a released toolchain's command takes.
    var release: String
    /// What a nightly toolchain's command takes.
    var nightly: String
    /// What a particular version adds to those.
    var overrides = VersionOverrides()

    /// The same arguments on every toolchain, for a build that takes none of the flags inputs.
    static func always(_ arguments: String) -> SwiftFlags {
        SwiftFlags(release: arguments, nightly: arguments)
    }

    /// The arguments one version's command runs with.
    func arguments(for version: String) -> [String] {
        let base = self.flags(nightly: version.hasPrefix("nightly-"))
        return self.split("\(base) \(self.overrides.arguments(for: version) ?? "")")
    }

    /// The arguments for a toolchain that has no version to look an override up by; this is
    /// how a swiftly snapshot takes the nightly flags.
    func arguments(nightly: Bool) -> [String] {
        self.split(self.flags(nightly: nightly))
    }

    private func flags(nightly: Bool) -> String {
        nightly ? self.nightly : self.release
    }

    /// A flags input as the arguments it names. Globbing never happens, so a wildcard reaches
    /// the runner as the argument the caller wrote.
    private func split(_ flags: String) -> [String] {
        flags.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

// MARK: - The groups

/// A group whose entries carry a `swift_build`: the Linux tests, the SDK builds, the Cxx
/// interop check, and Windows. They differ in the axes they fan out over, and in the machines
/// and images those axes name.
struct SwiftBuildJobs: JobGroup {
    var settings: JobGroupSettings
    var platform: MatrixEntry.Platform
    var minimum: MinimumVersion
    var releaseToken: String
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
    /// The NDK releases the entries fan out over, which only the Android SDK build has.
    var ndkVersions: [String]?
    /// Carried by the Android SDK build, telling the executor whether the emulator runs what
    /// the build produced.
    var androidEmulator: Bool?

    /// One entry's value from every axis.
    private struct Combination {
        var runner: Runner
        var image: ContainerImage?
        var ndkVersion: String?
        var variant: Commands.Variant
        var version: String
    }

    /// One pass per NDK release, or a single pass for a build with no NDK to name.
    private var ndkPasses: [String?] { self.ndkVersions?.map(Optional.some) ?? [nil] }

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
                                version: $0
                            )
                        }
                    }
                }
            }
        }
    }

    var entries: [MatrixEntry] {
        self.combinations.map { combination in
            let toolchain = Toolchain(version: combination.version, releaseToken: self.releaseToken)
            var sdk = self.sdk
            sdk?.ndkVersion = combination.ndkVersion
            return MatrixEntry(
                platform: self.platform,
                name: self.settings.name(
                    "\(self.settings.namePrefix) \(combination.version)",
                    combination.ndkVersion.map { "NDK \($0)" },
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
                commandArguments: self.flags.arguments(for: combination.version),
                env: self.environment,
                androidEmulator: self.androidEmulator
            )
        }
    }

    /// The command one entry runs. A group whose command is the check itself takes no
    /// per-version replacement.
    private func command(for combination: Combination) -> String {
        switch self.settings.commandSource {
        case .fixed:
            return combination.variant.command
        case .input:
            return self.settings.overrides.command(for: combination.version) ?? combination.variant.command
        }
    }
}

/// The macOS entries: one pass over the Xcode list, which names Xcodes, and one over the
/// Swift list, which names Swift versions. A label's versions select from whichever list holds
/// them, so a label naming an Xcode contributes nothing to the Swift pass.
struct MacOSJobs: JobGroup {
    var settings: JobGroupSettings
    var minimum: MinimumVersion
    var flags: SwiftFlags
    var setupCommand: String
    var environment: JSONValue
    var machines: MacOSMachines
    var targets: [XcodeTarget]
    var debugOutput: Bool
    /// What the Xcode pass's entry names carry before the version. The Swift pass takes the
    /// group's own prefix.
    let xcodeNamePrefix = "macOS Xcode"

    /// The Xcodes a label may select, which the group's Xcode list names.
    private var xcodeVersions: [String] { self.settings.versionsExemptFromMinimum }

    var entries: [MatrixEntry] {
        self.machines.runners.flatMap { runner in
            self.pass(self.xcodeVersions, on: runner, namePrefix: self.xcodeNamePrefix, namesXcode: true)
                + self.pass(
                    self.settings.versions,
                    on: runner,
                    namePrefix: self.settings.namePrefix,
                    namesXcode: false
                )
        }
    }

    private func pass(
        _ versions: [String],
        on runner: Runner,
        namePrefix: String,
        namesXcode: Bool
    ) -> [MatrixEntry] {
        if versions.isEmpty { return [] }
        return self.settings.commands.flatMap { variant in
            // The Xcode list names Xcodes, which the minimum Swift version does not order.
            variant.versions(among: versions).filter { namesXcode || self.minimum.admits($0) }.map { version in
                MatrixEntry(
                    platform: .macOS,
                    name: self.settings.name(
                        "\(namePrefix) \(version)",
                        self.machines.runners.count > 1 ? runner.name : nil,
                        for: variant
                    ),
                    runner: runner.labels,
                    xcodeBuild: MatrixEntry.XcodeBuild(
                        swiftVersion: namesXcode ? nil : version,
                        xcodeVersion: namesXcode ? version : nil,
                        targets: self.targets,
                        debugOutput: self.debugOutput
                    ),
                    setupCommand: self.setupCommand,
                    command: self.settings.overrides.command(for: version) ?? variant.command,
                    commandArguments: self.flags.arguments(for: version),
                    env: self.environment
                )
            }
        }
    }
}

/// The macOS entries driven by a swiftly-managed toolchain, which fan out over the toolchains
/// rather than a version list.
struct MacOSSwiftlyJobs: JobGroup {
    var settings: JobGroupSettings
    var flags: SwiftFlags
    var setupCommand: String
    var environment: JSONValue
    var machines: MacOSMachines
    var toolchains: [SwiftlyToolchain]

    func validate(against minimum: MinimumVersion) {
        self.validateSettings(against: minimum)
        // Skipping the entry would drop a job from a run that still reports success, which is how
        // a misspelled key goes unnoticed.
        for toolchain in self.toolchains
        where toolchain.xcodeVersion.isEmpty || toolchain.swiftlyToolchain.isEmpty {
            fatal(
                """
                macos_swiftly_toolchains entry needs both xcode_version and swiftly_toolchain: \
                xcode_version "\(toolchain.xcodeVersion)", swiftly_toolchain "\(toolchain.swiftlyToolchain)"
                """
            )
        }
    }

    var entries: [MatrixEntry] {
        self.toolchains.flatMap { toolchain in
            self.machines.runners(for: toolchain).flatMap { runner in
                self.settings.commands.map { variant in
                    MatrixEntry(
                        platform: .macOS,
                        name: self.settings.name(
                            "\(self.settings.namePrefix) \(toolchain.swiftlyToolchain) "
                                + "(Xcode \(toolchain.xcodeVersion))",
                            self.machines.operatingSystems.count > 1 ? runner.name : nil,
                            for: variant
                        ),
                        runner: runner.labels,
                        xcodeBuild: MatrixEntry.XcodeBuild(
                            xcodeVersion: toolchain.xcodeVersion,
                            swiftlyToolchain: toolchain.swiftlyToolchain
                        ),
                        setupCommand: self.setupCommand,
                        command: variant.command,
                        // A snapshot takes the nightly flags, as a "nightly-" prefix does elsewhere.
                        commandArguments: self.flags.arguments(
                            nightly: toolchain.swiftlyToolchain.contains("snapshot")
                        ),
                        env: self.environment
                    )
                }
            }
        }
    }
}

/// The FreeBSD entries, which carry a virtual machine and a toolchain URL rather than a
/// `swift_build`.
struct FreeBSDJobs: JobGroup {
    /// The one toolchain published for FreeBSD.
    private static let toolchainURL =
        "https://download.swift.org/tmp-ci-nightly/development/freebsd-14_ci_latest.tar.gz"

    var settings: JobGroupSettings
    var setupCommand: String
    var osVersions: [String]
    var buildFlags: String
    var environmentVariables: String

    func validate(against minimum: MinimumVersion) {
        self.validateSettings(against: minimum)
        // One FreeBSD toolchain is published, so a version naming anything else would produce a
        // job labeled for a toolchain it does not install.
        for version in self.settings.versions where version != "nightly-main" {
            fatal("FreeBSD supports only the nightly-main Swift version, not '\(version)'.")
        }
        // The published tarballs are named by major release and only 14 has one, so any other OS
        // version would install a toolchain built for a release the job is not labeled for.
        for osVersion in self.osVersions where osVersion != "14" && !osVersion.hasPrefix("14.") {
            fatal(
                "No Swift toolchain is published for FreeBSD \(osVersion); freebsd_os_versions supports 14 releases."
            )
        }
    }

    var entries: [MatrixEntry] {
        self.osVersions.flatMap { osVersion in
            self.settings.commands.flatMap { variant in
                variant.versions(among: self.settings.versions).map { version in
                    MatrixEntry(
                        platform: .freeBSD,
                        name: self.settings.name(
                            "\(self.settings.namePrefix) \(version) - \(osVersion) - x86_64",
                            for: variant
                        ),
                        runner: ["ubuntu-24.04"],
                        freeBSDBuild: MatrixEntry.FreeBSDBuild(
                            osVersion: osVersion,
                            swiftVersion: version,
                            swiftURL: FreeBSDJobs.toolchainURL,
                            buildFlags: self.buildFlags,
                            envVars: self.environmentVariables
                        ),
                        setupCommand: self.setupCommand,
                        command: variant.command,
                        commandArguments: [],
                        env: .object([:])
                    )
                }
            }
        }
    }
}

// MARK: - The matrix

/// The matrix, as the rest of the workflow reads it.
struct Matrix: Encodable {
    var config: [MatrixEntry]

    /// What the matrix is for. In toolchains mode the caller supplies the command, so an entry
    /// carries none of its own.
    enum Mode: String {
        case jobs
        case toolchains
    }

    /// The form the rest of the workflow parses the matrix with.
    enum Format: String {
        case yaml
        case json
    }

    /// The matrix as the rest of the workflow reads it, which jq and yq write.
    func encoded(as format: Format) -> String {
        let encoder = JSONEncoder()
        // Two runs of the same configuration have to produce the same matrix.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json: Data
        do {
            json = try encoder.encode(self)
        } catch {
            fatal("Could not encode the matrix: \(error)")
        }
        switch format {
        case .json: return jq.format(json, ["."])
        case .yaml: return yq.format(json, ["-P"])
        }
    }
}

/// One job the matrix holds.
struct MatrixEntry: Encodable {
    var platform: Platform
    var name: String
    var runner: [String]
    var swiftBuild: SwiftBuild?
    var xcodeBuild: XcodeBuild?
    var freeBSDBuild: FreeBSDBuild?
    /// Absent in toolchains mode, where the caller supplies these instead. `env` stays: it
    /// describes what the toolchain needs rather than the work run on it.
    var setupCommand: String?
    var command: String?
    var commandArguments: [String]?
    var env: JSONValue
    var androidEmulator: Bool?

    enum CodingKeys: String, CodingKey {
        case platform, name, runner, command, env
        case swiftBuild = "swift_build"
        case xcodeBuild = "xcode_build"
        case freeBSDBuild = "freebsd"
        case setupCommand = "setup_command"
        case commandArguments = "command_arguments"
        case androidEmulator = "android_emulator"
    }

    /// The entry as toolchains mode emits it: a machine and a toolchain, and no work of its own.
    var withoutCommands: MatrixEntry {
        var entry = self
        entry.setupCommand = nil
        entry.command = nil
        entry.commandArguments = nil
        return entry
    }

    /// What an entry runs on, which the executor dispatches on.
    enum Platform: String, Encodable {
        case linux = "Linux"
        case macOS = "macOS"
        case windows = "Windows"
        case freeBSD = "FreeBSD"
    }
}

extension MatrixEntry {
    /// The toolchain a Linux or Windows entry runs. The resolved forms are carried only when
    /// they differ from the label, so a hand-written matrix needs only `swift_version`.
    struct SwiftBuild: Encodable {
        var swiftVersion: String
        var resolvedVersion: String?
        var swiftlySelector: String?
        var sdk: SDK?
        var container: Container?

        init(_ toolchain: Toolchain, sdk: SDK? = nil, container: Container? = nil) {
            self.swiftVersion = toolchain.version
            self.resolvedVersion = toolchain.resolved == toolchain.version ? nil : toolchain.resolved
            self.swiftlySelector = toolchain.swiftly == toolchain.version ? nil : toolchain.swiftly
            self.sdk = sdk
            self.container = container
        }

        enum CodingKeys: String, CodingKey {
            case sdk, container
            case swiftVersion = "swift_version"
            case resolvedVersion = "toolchain"
            case swiftlySelector = "swiftly"
        }
    }

    /// The toolchain a macOS entry runs: an Xcode that ships one, or an Xcode with a
    /// swiftly-managed toolchain installed under it.
    struct XcodeBuild: Encodable {
        var swiftVersion: String?
        var xcodeVersion: String?
        var swiftlyToolchain: String?
        var targets: [XcodeTarget]?
        var debugOutput: Bool?

        enum CodingKeys: String, CodingKey {
            case targets
            case swiftVersion = "swift_version"
            case xcodeVersion = "xcode_version"
            case swiftlyToolchain = "swiftly_toolchain"
            case debugOutput = "debug_output"
        }
    }

    /// The virtual machine a FreeBSD entry runs in, and the toolchain it installs there.
    struct FreeBSDBuild: Encodable {
        var osVersion: String
        /// The executor derives SWIFT_VERSION from this: a FreeBSD entry has no `swift_build`.
        var swiftVersion: String
        var swiftURL: String
        var buildFlags: String
        var envVars: String

        enum CodingKeys: String, CodingKey {
            case osVersion = "os_version"
            case swiftVersion = "swift_version"
            case swiftURL = "swift_url"
            case buildFlags = "build_flags"
            case envVars = "env_vars"
        }
    }
}

extension MatrixEntry.SwiftBuild {
    /// The Swift SDK a build is made against, which install-and-build-with-sdk.sh installs.
    struct SDK: Encodable {
        var kind: Kind
        /// An NDK release is part of which SDK a build is made against, so it belongs beside the
        /// triples.
        var ndkVersion: String?
        var triples: [String]?

        enum CodingKeys: String, CodingKey {
            case triples
            case kind = "type"
            case ndkVersion = "ndk_version"
        }

        /// The SDKs a build can be made against.
        enum Kind: String, Encodable {
            case staticLinux = "static-linux"
            case wasm
            case embeddedWasm = "embedded-wasm"
            case android
        }
    }

    /// The container an entry runs in, as the workflow's `container:` block takes it.
    struct Container: Encodable {
        var image: String
        var dockerfile: String?
        var capabilities: [String]?
        var securityOptions: [String]?

        enum CodingKeys: String, CodingKey {
            case image, dockerfile, capabilities
            case securityOptions = "security_options"
        }
    }
}

// MARK: - Toolchains

/// A version label and the forms upstream publishes it under.
struct Toolchain {
    /// The label a caller wrote, such as `6.3` or `nightly-release`.
    let version: String
    /// The branch spelling upstream publishes the next release's nightly under, which
    /// `nightly-release` is an alias for: 6.0 through 6.3 were "6.<n>", 6.4 is "6.4.x".
    let releaseToken: String

    /// The Docker tag infix, the Windows installer script suffix, and the argument
    /// install-and-build-with-sdk.sh takes.
    var resolved: String {
        let alias = "nightly-\(self.releaseToken)"
        return self.version == "nightly-release" || self.version == alias ? alias : self.version
    }

    /// The swiftly selector. The branch token names the release snapshot's own directory under
    /// dev/, and swiftly's release-snapshot grammar takes it whole, so it is passed through.
    var swiftly: String {
        guard self.resolved.hasPrefix("nightly-") else { return self.resolved }
        let branch = String(self.resolved.dropFirst("nightly-".count))
        return branch == "main" ? "main-snapshot" : "\(branch)-snapshot"
    }

    /// The image this toolchain runs in on a distribution. Upstream publishes the nightlies
    /// under their own repository, so a nightly is not tagged like a release.
    func image(distribution: String) -> String {
        self.resolved.hasPrefix("nightly-")
            ? "swiftlang/swift:\(self.resolved)-\(distribution)"
            : "swift:\(self.resolved)-\(distribution)"
    }
}

// MARK: - Versions

/// A released Swift version, ordered by its components.
struct SwiftVersion: Comparable {
    private let components: [Int]

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        self.components = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    static func < (first: SwiftVersion, second: SwiftVersion) -> Bool {
        first.components.lexicographicallyPrecedes(second.components)
    }

    /// A version list entry, which is a number or a nightly label and nothing else. A label
    /// this cannot order would otherwise be silently kept or dropped.
    static func inVersionList(_ label: String) -> SwiftVersion {
        guard let version = SwiftVersion(label) else {
            fatal(
                """
                Cannot compare '\(label)' as a version. A Swift version list takes numbers like 6.3, or a \
                nightly- label; '\(label)' is neither.
                """
            )
        }
        return version
    }

    /// The newest release a version list holds, falling back to its last entry when the list is
    /// all nightlies.
    static func newestRelease(in versions: [String]) -> String {
        let releases = versions.filter { !$0.hasPrefix("nightly-") }
        let newest = releases.max { SwiftVersion.inVersionList($0) < SwiftVersion.inVersionList($1) }
        return newest ?? versions.last ?? ""
    }
}

/// The oldest toolchain the package builds on. A version below it cannot resolve the
/// manifest, so a job on it fails for a reason the caller did not ask about.
struct MinimumVersion {
    /// As the caller or the manifest wrote it, for the message.
    let text: String
    private let floor: SwiftVersion?

    init(_ text: String) {
        self.text = text
        if text.isEmpty || text == "none" {
            self.floor = nil
            return
        }
        guard let version = SwiftVersion(text) else {
            fatal(
                """
                Cannot compare '\(text)' as a version: minimum_swift_version must be a number like 6.3, 'none', \
                or empty.
                """
            )
        }
        self.floor = version
    }

    /// A nightly is always kept: it is not a released version this can order.
    func admits(_ label: String) -> Bool {
        guard let floor = self.floor else { return true }
        if label.hasPrefix("nightly-") { return true }
        return SwiftVersion.inVersionList(label) >= floor
    }

    /// What a caller does about a version the filter dropped. The filter is not an input of its
    /// own, so a message naming
    /// only what was dropped leaves them looking for a knob that isn't there.
    static let remedy =
        "The minimum comes from the manifest's swift-tools-version unless minimum_swift_version "
        + "overrides it, so raise the versions, or lower minimum_swift_version - 'none' turns the "
        + "filter off."
}

extension MinimumVersion {
    /// The oldest toolchain the package builds on: the version the caller named, or the lowest
    /// its manifests declare. Reading the manifests says what they declared.
    init(for configuration: Configuration) {
        if !configuration.minimumSwiftVersion.isEmpty {
            self.init(configuration.minimumSwiftVersion)
            return
        }
        let detected = MinimumVersion.detected(includingSubdirectories: configuration.searchSubdirectories)
        if !detected.isEmpty { log("Auto-detected minimum Swift tools version: \(detected)") }
        self.init(detected)
    }

    /// The lowest tools version the manifests declare, which is the oldest toolchain the package
    /// claims to build on.
    static func detected(includingSubdirectories: Bool) -> String {
        let fileManager = FileManager.default

        func manifests(in directory: String) -> [String] {
            let contents = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
            let versioned = contents.filter { $0.hasPrefix("Package@swift-") && $0.hasSuffix(".swift") }.sorted()
            return (["Package.swift"] + versioned).map { directory == "." ? $0 : "\(directory)/\($0)" }
        }

        var directories = ["."]
        if includingSubdirectories {
            let contents = (try? fileManager.contentsOfDirectory(atPath: ".")) ?? []
            directories += contents.filter { entry in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: entry, isDirectory: &isDirectory) && isDirectory.boolValue
            }.sorted().map { "./\($0)" }
        }

        var minimum: (version: SwiftVersion, text: String)?
        for path in directories.flatMap(manifests(in:)) {
            guard let declared = MinimumVersion.toolsVersion(ofManifestAt: path) else { continue }
            log("Found \(path) with tools-version: \(declared)")
            let version = SwiftVersion.inVersionList(declared)
            if let current = minimum, current.version <= version { continue }
            minimum = (version, declared)
        }
        return minimum?.text ?? ""
    }

    /// The tools version a manifest declares, or nil when there is no manifest to read or it
    /// declares none.
    private static func toolsVersion(ofManifestAt path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let contents: String
        do {
            contents = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            fatal("Could not read \(path): \(error)")
        }
        var line = contents.split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
        guard line.hasPrefix("//") else { return nil }
        line = line.dropFirst(2).drop(while: { $0 == " " })
        guard line.hasPrefix("swift-tools-version:") else { return nil }
        let version = line.dropFirst("swift-tools-version:".count).drop(while: { $0 == " " })
            .prefix { $0.isNumber || $0 == "." }
        return version.isEmpty ? nil : String(version)
    }
}

// MARK: - Commands

/// What a `*_command` input names: one command, or a map of label to command.
///
///   linux_command: swift test
///
///   linux_command: |
///     test: swift test
///     release:
///       command: swift build -c release
///       versions: ["6.3"]
struct Commands: InputDecodable, ExpressibleByStringLiteral {
    /// One command a group runs, and the label its jobs carry.
    struct Variant {
        var label: String
        var command: String
        var swiftVersions: [String]?

        init(label: String, command: String, swiftVersions: [String]?) {
            self.label = label
            self.command = command.trimmingTrailingNewlines
            self.swiftVersions = swiftVersions
        }

        /// The versions this variant runs on, in the group's own order rather than the label's.
        func versions(among available: [String]) -> [String] {
            guard let swiftVersions = self.swiftVersions else { return available }
            return available.filter(swiftVersions.contains)
        }
    }

    private var variants: [Variant]

    /// The label leading an entry's job name, which is nothing when the group runs one command:
    /// entry names are required status checks in adopting repositories.
    func nameLabel(for variant: Variant) -> String? {
        self.count > 1 ? variant.label : nil
    }

    init(_ command: String) {
        self.variants = [Variant(label: "", command: command, swiftVersions: nil)]
    }

    init(stringLiteral command: String) {
        self.init(command)
    }

    /// The parse only classifies. Anything but a map of labels is the command itself, taken
    /// byte for byte - including a value that is not YAML at all, such as
    /// `[ -f x ] && swift build`.
    ///
    /// A shell command can parse as a map: `swift test --filter Foo: Bar` yields one keyed on
    /// everything before the colon. Requiring every key to be a label leaves only
    /// `<word>: <rest>` ambiguous, and that names a program whose name ends in a colon, so it
    /// is not a command anyone would have run.
    init(input text: String, name: String) {
        self.variants =
            Commands.labeled(text, name: name) ?? [Variant(label: "", command: text, swiftVersions: nil)]
    }

    /// The variants a map of labels names, or nil when the value is the command itself.
    private static func labeled(_ text: String, name: String) -> [Variant]? {
        guard let parsed = Parsed(text) else { return nil }
        if parsed.isList {
            fatal(
                """
                \(name) takes a command, or a map of label to command such as {test: swift test}, but got a \
                list: \(text)
                """
            )
        }
        let members = parsed.mapMembers
        if members.isEmpty || members.contains(where: { !Commands.isLabel($0.key) }) { return nil }
        // A label written twice would run one command of the two the caller named, and under the
        // bare name, since one command earns no label.
        guard Set(members.map(\.key)).count == members.count else {
            fatal("\(name) names a label more than once: \(text)")
        }

        // A label carrying anything else - a number, a misspelled key, a blank command, an empty
        // version list - would leave the job running the group's default command under a name
        // that says otherwise, or produce no job for that label at all.
        let malformed = members.filter { settings(of: $0.value) == nil }
        guard malformed.isEmpty else {
            let reported = malformed.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            fatal(
                """
                \(name) takes each label's command as a non-blank string, or a map of command and a non-empty \
                versions list, but got: \(reported)
                """
            )
        }
        return members.compactMap { member in
            settings(of: member.value).map {
                Variant(label: member.key, command: $0.command, swiftVersions: $0.versions)
            }
        }
    }

    /// The command and versions a label carries, or nil when it carries no usable command.
    private static func settings(of value: JSONValue) -> (command: String, versions: [String]?)? {
        if let command = value.asString {
            return command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : (command, nil)
        }
        guard case .object(let settings) = value,
            Set(settings.keys).subtracting(["command", "versions"]).isEmpty,
            let command = settings["command"]?.asString,
            !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        guard let listed = settings["versions"]?.nonNull else { return (command, nil) }
        guard let versions = listed.asArray, versions.isEmpty == false,
            versions.allSatisfy({ $0.asString != nil })
        else {
            return nil
        }
        return (command, versions.map(\.text))
    }

    /// A label leads the job name, so it is a word. That is also what keeps a shell command
    /// YAML reads as a map from being mistaken for one.
    private static func isLabel(_ text: String) -> Bool {
        guard let first = text.first, first.isASCII, first.isLetter || first.isNumber else { return false }
        return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) }
    }
}

/// One command each, and never none: a value that is not a map of labels is itself the
/// command, so there is always something to run.
extension Commands: RandomAccessCollection {
    var startIndex: Int { self.variants.startIndex }
    var endIndex: Int { self.variants.endIndex }
    subscript(position: Int) -> Variant { self.variants[position] }
}

extension String {
    /// The text without the newlines it ends with, which is how a command reaches the runner:
    /// a YAML block scalar ends with one, and `swift build\n` is the command `swift build`.
    fileprivate var trimmingTrailingNewlines: String {
        var text = self
        while text.hasSuffix("\n") { text.removeLast() }
        return text
    }
}

// MARK: - Version overrides

/// What a `*_version_overrides` input carries: for one version, arguments to add, or a
/// command to replace.
///
///   linux_version_overrides: |
///     6.2: -Xswiftc -warnings-as-errors
///     nightly-main:
///       command: swift build
///       arguments: --explicit-target-dependency-import-check error
struct VersionOverrides: InputDecodable {
    /// What one version's key carries.
    private struct Override {
        var version: String
        var arguments: String?
        var command: String?

        init(version: String, arguments: String?, command: String?) {
            self.version = version
            self.arguments = arguments
            self.command = command?.trimmingTrailingNewlines
        }
    }

    /// The input these were read from, which a message names so the caller knows which knob to
    /// turn. Empty for the default, which carries no overrides for a message to be about.
    private(set) var name = ""
    private var overrides: [Override] = []

    var isEmpty: Bool { self.overrides.isEmpty }
    var versions: [String] { self.overrides.map(\.version) }

    init() {}

    /// What a version's override adds to the flags, if it names any.
    func arguments(for version: String) -> String? {
        self.override(for: version)?.arguments
    }

    /// The command a version's override replaces the group's with, if it names one.
    func command(for version: String) -> String? {
        self.override(for: version)?.command
    }

    /// A version written twice takes the last of its overrides, which is what jq would do
    /// reading these into an object: the
    /// members are kept in the order they were written so that a repeated key can be seen.
    private func override(for version: String) -> Override? {
        self.overrides.last { $0.version == version }
    }

    /// The versions this replaces the command for, of those a group runs. A key naming a version
    /// the group's own list does not hold reaches none of its entries.
    func versionsReplacingTheCommand(among groupVersions: [String]) -> [String] {
        self.overrides.filter { $0.command != nil && groupVersions.contains($0.version) }.map(\.version)
    }

    /// The override for a version is read by looking the version up, so a value of any other
    /// shape is absent rather than wrong: the arguments the caller asked for go missing from a
    /// job that still passes, which is how a repository loses warnings-as-errors.
    init(input text: String, name: String) {
        self.name = name
        guard let parsed = Parsed(text) else {
            fatal("\(name) is not valid JSON or YAML: \(text)")
        }
        // A value that carried nothing - blank, or an explicit null - is no overrides rather
        // than a malformed map.
        if parsed.value.isNull { return }
        guard parsed.isMap else {
            fatal(
                """
                \(name) must be a map of version to override, such as {"6.3": "-Xswiftc -warnings-as-errors"}, \
                but got: \(text)
                """
            )
        }

        let members = parsed.mapMembers
        let notOverrides = members.filter {
            if case .object = $0.value { return false }
            return $0.value.asString == nil
        }
        guard notOverrides.isEmpty else {
            let reported = notOverrides.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            fatal(
                "\(name) takes the arguments as a string, or a map with command and arguments, but got: \(reported)"
            )
        }

        // A misspelled key inside the map, or a value that is not a string, carries nothing while
        // looking as though it does.
        let malformed = members.filter { member in
            guard case .object(let settings) = member.value else { return false }
            return !Set(settings.keys).subtracting(["arguments", "command"]).isEmpty
                || settings.values.contains { $0.asString == nil }
        }
        guard malformed.isEmpty else {
            let reported = malformed.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            fatal("\(name) takes command and arguments, each a string, but got: \(reported)")
        }

        self.overrides = members.map { member in
            Override(
                version: member.key,
                arguments: member.value.asString ?? member.value["arguments"]?.asString,
                command: member.value["command"]?.asString
            )
        }
    }

    /// Fails when a key names no version any enabled group runs. The arguments it carries are
    /// silently lost otherwise, which is how a version rename drops warnings-as-errors.
    func validateKeys(against runnableVersions: [String]) {
        if self.isEmpty { return }
        // No versions means no enabled group reads these, so a key names nothing because nothing
        // runs. Failing there would take down the platforms that are enabled.
        if runnableVersions.isEmpty {
            log("WARNING: ignoring \(self.name): no enabled job group reads it")
            return
        }
        for key in self.versions where !runnableVersions.contains(key) {
            fatal(
                """
                \(self.name) override key '\(key)' does not match any version in the matrix. Valid keys: \
                \(runnableVersions.joined(separator: " "))
                """
            )
        }
    }
}

// MARK: - Inputs

/// An input. A value that carries nothing - unset, or the empty string Actions passes for an
/// input a caller left out - takes the declared default, which is already the parsed form.
@propertyWrapper
struct Input<Value: InputDecodable> {
    var wrappedValue: Value

    init(wrappedValue defaultValue: Value, _ variable: String) {
        self.wrappedValue = Input.read(variable, default: defaultValue)
    }

    /// What an environment variable carries, or the default when it carries nothing.
    static func read(_ variable: String, default defaultValue: Value) -> Value {
        let text = ProcessInfo.processInfo.environment[variable] ?? ""
        return text.isEmpty ? defaultValue : Value(input: text, name: variable.lowercased())
    }
}

/// A value an input can carry. The conformance is where that shape's rules live: an input
/// carrying the wrong shape fails the run rather than contributing nothing.
protocol InputDecodable {
    init(input text: String, name: String)
}

/// An element of a list input.
protocol InputElement {
    /// - Parameters:
    ///   - element: the element as it parsed.
    ///   - text: the element as it was written, which is not the same for a number.
    init(element: JSONValue, text: String)
}

extension String: InputDecodable, InputElement {
    init(input text: String, name: String) { self = text }
    init(element: JSONValue, text: String) { self = text }
}

extension Bool: InputDecodable {
    /// Anything but `true` is off, which is what an unset input is.
    init(input text: String, name: String) { self = text == "true" }
}

extension Array: InputDecodable where Element: InputElement {
    /// A value of another shape would contribute no entries: the platform would be absent from
    /// a run that still reports success.
    init(input text: String, name: String) {
        guard let parsed = Parsed(text) else {
            fatal("\(name) is not valid JSON or YAML: \(text)")
        }
        guard let items = parsed.value.asArray else {
            fatal("\(name) must be a list, such as [\"a\", \"b\"], but got: \(text)")
        }
        self = zip(items, parsed.listElements).map(Element.init(element:text:))
    }
}

extension JSONValue: InputDecodable {
    /// An input passed through to the entry, such as an environment block.
    init(input text: String, name: String) {
        guard let parsed = Parsed(text) else {
            fatal("\(name) is not valid JSON or YAML: \(text)")
        }
        guard parsed.isMap || parsed.value.isNull else {
            fatal("\(name) must be a map of name to value, such as {FOO: bar}, but got: \(text)")
        }
        self = parsed.value.isNull ? .object([:]) : parsed.value
    }
}

/// A Swift SDK build: the SDK its entries build against, and the inputs that configure them,
/// which all share one prefix.
struct SDKBuild {
    /// The prefix every one of its inputs shares.
    let prefix: String
    let kind: MatrixEntry.SwiftBuild.SDK.Kind
    /// What its job names lead with.
    let name: String

    let enabled: Bool
    let versions: [String]
    let commands: Commands
    let setupCommand: String

    init(prefix: String, kind: MatrixEntry.SwiftBuild.SDK.Kind, name: String) {
        self.prefix = prefix
        self.kind = kind
        self.name = name
        let variable = prefix.uppercased()
        self.enabled = Input.read("ENABLE_\(variable)_BUILD", default: false)
        self.versions = Input.read("\(variable)_VERSIONS", default: Configuration.defaultSDKVersions)
        self.commands = Input.read("\(variable)_COMMAND", default: "swift build")
        self.setupCommand = Input.read("\(variable)_SETUP_COMMAND", default: "")
    }

    /// The input that turns this build on.
    var enableInput: String { "enable_\(self.prefix)_build" }
    /// The input naming the Swift versions it builds on.
    var versionsInput: String { "\(self.prefix)_versions" }
    /// The input naming what it runs.
    var commandInput: String { "\(self.prefix)_command" }
}

/// An input naming one OS, or a list of them.
///
/// Only a list is taken from the parse: a single value is used exactly as it was written,
/// because YAML reads `24.10` as the number 24.1 and drops everything after a ` #`, and no
/// image is tagged 6.3-24.1.
struct OSList: InputDecodable, ExpressibleByStringLiteral {
    var names: [String]

    init(_ name: String) {
        self.names = [name]
    }

    init(stringLiteral name: String) {
        self.init(name)
    }

    init(input text: String, name: String) {
        guard let parsed = Parsed(text) else {
            fatal("\(name) is not valid JSON or YAML: \(text)")
        }
        if parsed.isList {
            self.names = [String](input: text, name: name)
        } else if parsed.isMap {
            fatal("\(name) must be a name or a list of them, such as [\"a\", \"b\"], but got: \(text)")
        } else {
            self.names = [text]
        }
    }
}

/// A macOS entry driven by a swiftly-managed toolchain rather than the Xcode that ships one.
struct SwiftlyToolchain: InputElement {
    var xcodeVersion = ""
    var swiftlyToolchain = ""
    /// An entry naming its own OS runs there alone; the rest fan out over macos_os.
    var osVersion: String?
    var architecture: String?

    init(xcodeVersion: String, swiftlyToolchain: String) {
        self.xcodeVersion = xcodeVersion
        self.swiftlyToolchain = swiftlyToolchain
    }

    init(element: JSONValue, text: String) {
        let known = ["xcode_version", "swiftly_toolchain", "os_version", "arch"]
        let unknown = Set(element.asObject?.keys ?? [:].keys).subtracting(known).sorted()
        if !unknown.isEmpty {
            fatal(
                """
                macos_swiftly_toolchains includes unknown keys: \(unknown.joined(separator: ", ")). \
                An entry takes xcode_version, swiftly_toolchain, os_version and arch.
                """
            )
        }
        self.xcodeVersion = element["xcode_version"]?.text ?? ""
        self.swiftlyToolchain = element["swiftly_toolchain"]?.text ?? ""
        self.osVersion = element["os_version"]?.text
        self.architecture = element["arch"]?.text
    }
}

// MARK: - JSON

/// A value of any shape, which is what an input carries before its shape is known.
enum JSONValue: Codable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Each `try?` asks "is it this shape," so a failure is the answer rather than an error
        // to swallow. The order is the one JSON allows: an integer also decodes as a double.
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let items): try container.encode(items)
        case .object(let members): try container.encode(members)
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }

    var asObject: [String: JSONValue]? {
        guard case .object(let members) = self else { return nil }
        return members
    }

    var asString: String? {
        guard case .string(let text) = self else { return nil }
        return text
    }

    var asBool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var asArray: [JSONValue]? {
        guard case .array(let items) = self else { return nil }
        return items
    }

    /// The value, or nil when it carried nothing: an absent setting and an explicit null are
    /// the same answer.
    var nonNull: JSONValue? { self.isNull ? nil : self }

    var isNull: Bool {
        guard case .null = self else { return false }
        return true
    }

    /// The value as one line of text, the way `jq -r` writes it. A version list written
    /// `[6.3]` still names the version `6.3`.
    var text: String {
        self.asString ?? self.description
    }
}

extension JSONValue: CustomStringConvertible {
    /// The value as JSON on one line, which is how a message quotes back what a caller wrote.
    var description: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .integer(let value): return String(value)
        case .number(let value): return String(value)
        case .string(let text): return JSONValue.quoted(text)
        case .array(let items): return "[" + items.map(\.description).joined(separator: ",") + "]"
        case .object(let members):
            // Sorted so a message quoting a caller's value back reads the same on every run: a
            // dictionary has no order of its own.
            let written = members.sorted { $0.key < $1.key }
            return "{" + written.map { "\(JSONValue.quoted($0.key)):\($0.value)" }.joined(separator: ",") + "}"
        }
    }

    static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where scalar.value < 0x20: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}

// MARK: - Reading a value with yq

/// A value as yq read it: its YAML tag, and - for a map - its members in the order they were
/// written, a key written twice included.
struct Parsed: Decodable {
    struct Member: Decodable {
        var key: String
        var value: JSONValue
    }

    private var tag: String
    var value: JSONValue
    /// One element holding the members when the value is a map, and empty otherwise: the filter
    /// uses `select`, which yields one result or none, and yq has no conditional that returns
    /// a value either way. `mapMembers` is what a caller reads.
    private var members: [[Member]]
    /// The same, for a list's elements as they were written.
    private var elements: [[String]]

    var isList: Bool { self.tag == "!!seq" }
    var isMap: Bool { self.tag == "!!map" }
    var isCollection: Bool { self.isList || self.isMap }
    var mapMembers: [Member] { self.members.first ?? [] }
    /// A list's elements as text. YAML reads `24.10` as the number 24.1, and no image is tagged
    /// 6.3-24.1, so the token the caller wrote is what a name is taken from.
    var listElements: [String] { self.elements.first ?? [] }

    /// Reads a value the way yq does. Nil means the value is neither YAML nor JSON; two callers
    /// distinguish that from a value of the wrong shape.
    init?(_ text: String) {
        let result = yq.run(["-o=json", "-I=0", Parsed.filter], input: text)
        guard result.worked else { return nil }
        do {
            self = try JSONDecoder().decode(Parsed.self, from: result.standardOutput)
        } catch {
            fatal("yq produced JSON this generator could not read: \(error)")
        }
    }

    /// A value's shape, its members and its elements in one pass. `tostring` is applied to the
    /// copies in `members` and `elements` and to nothing else, so `value` keeps the original
    /// types: `versions: [6.3]` stays a number for the label's settings check to reject it.
    private static let filter = """
        {"tag": tag, "value": ., \
        "members": [select(tag == "!!map") | to_entries | map({"key": (.key | tostring), "value": .value})], \
        "elements": [select(tag == "!!seq") | map(tostring)]}
        """
}

// MARK: - Running jq and yq

/// A program this generator shells out to.
struct Tool {
    /// What one run of a tool wrote.
    struct Output {
        var standardOutput: Data
        var standardError: String
        var worked: Bool
    }

    /// The file name it was looked up under, which a message names.
    let name: String
    private let executable: URL

    /// Looks a program up on PATH, as a shell would.
    init(_ name: String) {
        #if os(Windows)
        let pathSeparator: Character = ";"
        self.name = name + ".exe"
        #else
        let pathSeparator: Character = ":"
        self.name = name
        #endif
        for variable in ["PATH", "Path"] {
            let paths = ProcessInfo.processInfo.environment[variable] ?? ""
            for directory in paths.split(separator: pathSeparator) {
                let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(self.name)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    self.executable = candidate
                    return
                }
            }
        }
        fatal("\(self.name) not found on PATH")
    }

    /// Runs the program over a value, and reports what it wrote.
    func run(_ arguments: [String], input: String) -> Output {
        let process = Process()
        process.executableURL = self.executable
        process.arguments = arguments
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            fatal("Could not run \(self.executable.path): \(error)")
        }

        // The value goes in on another thread: a matrix larger than the pipe's buffer would
        // otherwise fill it while nothing is reading the other end yet.
        DispatchQueue.global().async {
            standardInput.fileHandleForWriting.write(Data(input.utf8))
            standardInput.fileHandleForWriting.closeFile()
        }
        // Both streams are drained at once, for the same reason: whichever went unread could fill
        // and stall the tool while this waits on the other.
        //
        // nonisolated(unsafe) because the write happens before the group's wait returns, which the
        // compiler cannot see.
        nonisolated(unsafe) var diagnostic = Data()
        let draining = DispatchGroup()
        DispatchQueue.global().async(group: draining) {
            diagnostic = standardError.fileHandleForReading.readDataToEndOfFile()
        }
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        draining.wait()
        process.waitUntilExit()

        return Output(
            standardOutput: output,
            standardError: String(decoding: diagnostic, as: UTF8.self),
            worked: process.terminationStatus == 0
        )
    }

    /// The matrix as this tool rewrites it.
    func format(_ matrix: Data, _ arguments: [String]) -> String {
        let result = self.run(arguments, input: String(decoding: matrix, as: UTF8.self))
        guard result.worked else {
            fatal("\(self.name) could not format the matrix: \(result.standardError)")
        }
        return String(decoding: result.standardOutput, as: UTF8.self)
    }
}

// MARK: - Diagnostics

/// Diagnostics go to standard error; standard output carries the matrix.
func log(_ message: String) {
    FileHandle.standardError.write(Data("** \(message)\n".utf8))
}

/// Reports a configuration that would produce a matrix without the jobs the caller asked
/// for, and stops. A green run missing those jobs is what every one of these prevents.
func fatal(_ message: String) -> Never {
    FileHandle.standardError.write(Data("** ERROR: \(message)\n".utf8))
    exit(1)
}

// MARK: - Body of the script

let jq = Tool("jq")
let yq = Tool("yq")

// Populates the configuration from the environment, through the `@Input` initializers.
let config = Configuration()

guard let mode = Matrix.Mode(rawValue: config.matrixMode) else {
    fatal("MATRIX_MODE must be 'jobs' or 'toolchains', got '\(config.matrixMode)'")
}
guard let format = Matrix.Format(rawValue: config.matrixFormat) else {
    fatal("MATRIX_FORMAT must be 'yaml' or 'json', got '\(config.matrixFormat)'")
}
config.validatePairings(in: mode)

let generator = Generator(config, mode: mode)
let jobMatrix = generator.generate()

print(jobMatrix.encoded(as: format), terminator: "")

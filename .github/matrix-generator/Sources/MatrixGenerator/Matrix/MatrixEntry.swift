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
  /// Absent where the executor's own timeout applies.
  var timeoutMinutes: Int?

  enum CodingKeys: String, CodingKey {
    case platform, name, runner, command, env
    case timeoutMinutes = "timeout_minutes"
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

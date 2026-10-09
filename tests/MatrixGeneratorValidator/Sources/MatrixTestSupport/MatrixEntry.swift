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

/// One entry in a generated matrix: a toolchain, where to run it, and what to run.
///
/// Decoding is itself an assertion. A required field the generator renames or
/// stops emitting fails to decode, so no test has to ask about it. The optional
/// fields are the ones the generator emits only when they carry information, so
/// `nil` is a meaningful answer rather than a missing case.
public struct MatrixEntry: Decodable, Sendable {
  public var platform: String
  public var name: String
  public var runner: [String]

  /// Toolchain configuration for Swift on Linux and Windows. Absent on macOS and
  /// FreeBSD entries.
  public var swiftBuild: SwiftBuild?

  /// Toolchain configuration for macOS via Xcode. Absent everywhere else.
  public var xcodeBuild: XcodeBuild?

  /// Configuration for the FreeBSD virtual machine. Absent everywhere else.
  public var freebsd: FreeBSD?

  /// Omitted in toolchain-only mode, where the caller supplies them instead.
  public var command: String?
  public var setupCommand: String?
  public var commandArguments: [String]?

  public var env: [String: String]
  public var androidEmulator: Bool?

  public struct SwiftBuild: Decodable, Sendable {
    /// The version label a caller wrote, such as `6.3` or `nightly-release`.
    public var swiftVersion: String
    /// The concrete toolchain upstream publishes under. Emitted only when it
    /// differs from `swift_version`.
    public var toolchain: String?
    /// The swiftly selector. Emitted only when it differs from `swift_version`.
    public var swiftly: String?
    public var container: Container?
    public var sdk: SDK?
  }

  public struct Container: Decodable, Sendable {
    public var image: String
    public var dockerfile: String?
    public var capabilities: [String]?
    public var securityOptions: [String]?
  }

  public struct SDK: Decodable, Sendable {
    public var type: String
    public var ndkVersion: String?
    public var triples: [String]?
  }

  public struct XcodeBuild: Decodable, Sendable {
    /// Selects `Xcode_swift_<version>.app`.
    public var swiftVersion: String?
    /// Selects `Xcode_<version>.app`, or `Xcode-latest.app` for `latest-beta`.
    public var xcodeVersion: String?
    /// A swiftly selector installed under the selected Xcode.
    public var swiftlyToolchain: String?
    public var targets: [Target]?
    public var debugOutput: Bool?
  }

  public struct Target: Decodable, Sendable {
    public var platform: String
    public var scheme: String
    public var buildDestination: String
    public var testDestination: String
    public var build: Bool
    public var test: Bool
  }

  public struct FreeBSD: Decodable, Sendable {
    public var osVersion: String
    /// The version label, which the executor uses for `SWIFT_VERSION`. FreeBSD
    /// entries have no `swift_build`, so it lives here.
    public var swiftVersion: String
    public var swiftURL: String
    public var buildFlags: String
    public var envVars: String

    enum CodingKeys: String, CodingKey {
      case osVersion = "os_version"
      case swiftVersion = "swift_version"
      case swiftURL = "swift_url"
      case buildFlags = "build_flags"
      case envVars = "env_vars"
    }
  }
}

/// The generator emits snake_case. Every key is spelled out rather than relying on
/// a conversion strategy, so a renamed key fails to decode.
extension MatrixEntry {
  enum CodingKeys: String, CodingKey {
    case platform
    case name
    case runner
    case swiftBuild = "swift_build"
    case xcodeBuild = "xcode_build"
    case freebsd
    case command
    case setupCommand = "setup_command"
    case commandArguments = "command_arguments"
    case env
    case androidEmulator = "android_emulator"
  }
}

extension MatrixEntry.SwiftBuild {
  enum CodingKeys: String, CodingKey {
    case swiftVersion = "swift_version"
    case toolchain
    case swiftly
    case container
    case sdk
  }
}

extension MatrixEntry.Container {
  enum CodingKeys: String, CodingKey {
    case image
    case dockerfile
    case capabilities
    case securityOptions = "security_options"
  }
}

extension MatrixEntry.SDK {
  enum CodingKeys: String, CodingKey {
    case type
    case ndkVersion = "ndk_version"
    case triples
  }
}

extension MatrixEntry.XcodeBuild {
  enum CodingKeys: String, CodingKey {
    case swiftVersion = "swift_version"
    case xcodeVersion = "xcode_version"
    case swiftlyToolchain = "swiftly_toolchain"
    case targets
    case debugOutput = "debug_output"
  }
}

extension MatrixEntry.Target {
  enum CodingKeys: String, CodingKey {
    case platform
    case scheme
    case buildDestination = "build_destination"
    case testDestination = "test_destination"
    case build
    case test
  }
}

struct Matrix: Decodable {
  var config: [MatrixEntry]
}

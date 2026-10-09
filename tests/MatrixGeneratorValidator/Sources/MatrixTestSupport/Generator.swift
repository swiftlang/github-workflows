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

/// What one run of the generator produced.
public struct Generated: Sendable {
  public var entries: [MatrixEntry]
  public var standardError: String
  public var exitCode: Int32

  public var names: [String] { entries.map(\.name) }
  public var platforms: [String] { entries.map(\.platform) }
  /// The version label of every entry that has a Swift toolchain.
  public var versions: [String] { entries.compactMap { $0.swiftBuild?.swiftVersion } }
  public var count: Int { entries.count }

  public func entry(named name: String) -> MatrixEntry? {
    entries.first { $0.name == name }
  }
}

public enum GeneratorError: Error, CustomStringConvertible {
  case generatorNotFound(String)
  case toolNotFound(String)
  case decodingFailed(underlying: any Error, json: String, standardError: String)

  public var description: String {
    switch self {
    case .generatorNotFound(let path):
      return "generate-matrix.swift not found at \(path)"
    case .toolNotFound(let tool):
      return "\(tool) is required to run these tests but was not found on PATH"
    case .decodingFailed(let underlying, let json, let standardError):
      return """
        Could not decode the generated matrix: \(underlying)

        JSON:
        \(json)

        Generator stderr:
        \(standardError)
        """
    }
  }
}

/// Runs `generate-matrix.swift` and decodes what it emitted.
///
/// This needs no runner, no Swift toolchain for the package under test and no
/// network. The generator does read `Package.swift` from its working directory,
/// so runs happen in a scratch directory the helper writes manifests into.
public struct Generator: Sendable {
  /// Overridable so CI can point at a checkout elsewhere; otherwise derived from
  /// this file's location.
  public static var scriptPath: String {
    if let override = ProcessInfo.processInfo.environment["GENERATE_MATRIX_PATH"] {
      return override
    }
    // <root>/tests/MatrixGeneratorValidator/Sources/MatrixTestSupport/Generator.swift
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
      url.deleteLastPathComponent()
    }
    return url.appendingPathComponent(".github/workflows/scripts/matrix/generate-matrix.swift").path
  }

  /// Runs the generator and returns its raw output, for tests about the output
  /// itself rather than the matrix it describes.
  public static func runRaw(
    _ environment: [String: String] = [:],
    manifests: [String: String] = [:],
    includePlatformDefaults: Bool = false
  ) throws -> (standardOutput: String, standardError: String, exitCode: Int32) {
    let script = scriptPath
    guard FileManager.default.isExecutableFile(atPath: script) else {
      throw GeneratorError.generatorNotFound(script)
    }

    let workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("matrix-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDirectory) }

    for (name, contents) in manifests {
      try contents.write(
        to: workDirectory.appendingPathComponent(name),
        atomically: true,
        encoding: .utf8
      )
    }

    var variables = ProcessInfo.processInfo.environment
    if !includePlatformDefaults {
      variables["ENABLE_LINUX"] = "false"
      variables["ENABLE_WINDOWS"] = "false"
    }
    for (key, value) in environment {
      variables[key] = value
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: script)
    process.environment = variables
    process.currentDirectoryURL = workDirectory

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    try process.run()
    // Read before waiting: a full pipe buffer would otherwise deadlock.
    let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return (
      String(decoding: outputData, as: UTF8.self),
      String(decoding: errorData, as: UTF8.self),
      process.terminationStatus
    )
  }

  /// Runs the generator in a scratch directory and decodes the matrix.
  ///
  /// - Parameters:
  ///   - environment: Variables for this run. Linux and Windows are disabled first
  ///     so a test sees only the entries it is about; pass
  ///     `includePlatformDefaults` to keep the generator's own defaults.
  ///   - manifests: Files to write into the scratch directory before running,
  ///     keyed by name - how minimum-version detection is given something to read.
  ///   - includePlatformDefaults: Leave the platform enables alone.
  public static func run(
    _ environment: [String: String] = [:],
    manifests: [String: String] = [:],
    includePlatformDefaults: Bool = false
  ) throws -> Generated {
    // Ask for JSON so there is nothing to convert. A caller may still override
    // the format, which is how the format itself gets tested.
    var variables = ["MATRIX_FORMAT": "json"]
    for (key, value) in environment {
      variables[key] = value
    }

    let result = try runRaw(
      variables,
      manifests: manifests,
      includePlatformDefaults: includePlatformDefaults
    )

    // A failing generator produces no matrix, which is a legitimate thing for a
    // test to assert on, so report it rather than throwing.
    let trimmed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return Generated(entries: [], standardError: result.standardError, exitCode: result.exitCode)
    }

    do {
      let matrix = try JSONDecoder().decode(Matrix.self, from: Data(result.standardOutput.utf8))
      return Generated(
        entries: matrix.config,
        standardError: result.standardError,
        exitCode: result.exitCode
      )
    } catch {
      throw GeneratorError.decodingFailed(
        underlying: error,
        json: result.standardOutput,
        standardError: result.standardError
      )
    }
  }

  /// A manifest with the given tools version, for minimum-version detection.
  public static func manifest(toolsVersion: String) -> String {
    "// swift-tools-version:\(toolsVersion)\n"
  }
}

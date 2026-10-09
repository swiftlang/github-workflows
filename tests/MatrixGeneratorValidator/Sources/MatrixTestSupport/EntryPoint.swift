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

/// A workflow that calls the generator, and the environment it hands it.
///
/// The environment is read out of the workflow file: every `${{ inputs.x }}` in
/// its matrix-generating step becomes that input's declared default. A test can
/// then ask what a caller who passes nothing actually gets, so a default edited
/// in the workflow and a default edited in the generator are both visible.
public struct EntryPoint: Sendable, CustomStringConvertible {
  /// The workflow's file name without its extension.
  public let workflow: String

  public init(workflow: String) {
    self.workflow = workflow
  }

  public var description: String { workflow }

  public static let packageTest = EntryPoint(workflow: "package_test")
  public static let toolchainMatrix = EntryPoint(workflow: "toolchain_matrix")
  public static let benchmarks = EntryPoint(workflow: "benchmarks")

  /// Every workflow that generates a matrix by calling the generator.
  public static let all: [EntryPoint] = [packageTest, toolchainMatrix, benchmarks]

  /// Overridable so CI can point at a checkout elsewhere; otherwise derived from
  /// the generator's location, which sits in the same checkout.
  public var path: String {
    // <root>/.github/workflows/scripts/matrix/generate-matrix.swift
    var url = URL(fileURLWithPath: Generator.scriptPath)
    for _ in 0..<3 {
      url.deleteLastPathComponent()
    }
    return url.appendingPathComponent("\(workflow).yml").path
  }

  /// The enables that gate a whole block of the generator. A knob only one block
  /// reads is dead while that block is off, so a test comparing defaults turns
  /// these on first.
  public static let jobKindEnables = [
    "ENABLE_LINUX",
    "ENABLE_MACOS",
    "ENABLE_MACOS_SWIFTLY",
    "ENABLE_WINDOWS",
    "ENABLE_FREEBSD",
    "ENABLE_LINUX_STATIC_SDK_BUILD",
    "ENABLE_WASM_SDK_BUILD",
    "ENABLE_EMBEDDED_WASM_SDK_BUILD",
    "ENABLE_ANDROID_SDK_BUILD",
    "ENABLE_ANDROID_EMULATOR_TESTS",
    "ENABLE_CXX_INTEROP",
  ]

  /// What the matrix-generating step sets, with each input resolved to its
  /// declared default: the environment a caller who passes nothing produces.
  ///
  /// A value assembled in the step's script rather than its `env` block is not
  /// here, so `benchmarks.yml`'s composed commands and environment variables are
  /// absent - they are the workflow's own work, not a default a caller sees.
  public func environment(repositoryOwner: String = "swiftlang") throws -> [String: String] {
    let defaults = try inputDefaults()
    var resolved: [String: String] = [:]
    for (key, value) in try stepEnvironment() {
      if let input = Self.inputReference(in: value) {
        guard let declared = defaults[input] else {
          throw WorkflowError.unknownInput(workflow: workflow, key: key, input: input)
        }
        resolved[key] = declared
      } else if value.contains("${{ github.repository_owner }}") {
        resolved[key] = repositoryOwner
      } else if value.contains("${{ steps.") {
        // Where the scripts were checked out, which the test supplies itself.
        continue
      } else if value.contains("${{") {
        throw WorkflowError.unresolvedExpression(workflow: workflow, key: key, value: value)
      } else {
        resolved[key] = value
      }
    }
    return resolved
  }

  /// The keys of `environment()` that carry an input's declared default, rather
  /// than a value the workflow fixes for every caller.
  public func inputBackedKeys() throws -> Set<String> {
    var keys: Set<String> = []
    for (key, value) in try stepEnvironment() where Self.inputReference(in: value) != nil {
      keys.insert(key)
    }
    return keys
  }

  /// Every input's declared default, as the string Actions would pass.
  public func inputDefaults() throws -> [String: String] {
    let declarations = try yq(
      ".on.workflow_call.inputs",
      as: [String: InputDeclaration].self
    )
    return declarations.mapValues { $0.default?.value ?? "" }
  }

  /// The `env` block of the step that runs the generator.
  private func stepEnvironment() throws -> [String: String] {
    let blocks = try yq(
      #"[.jobs.*.steps[] | select(.id == "generate") | .env]"#,
      as: [[String: ActionsScalar]].self
    )
    guard let block = blocks.first else {
      throw WorkflowError.noGenerateStep(workflow: workflow)
    }
    return block.mapValues(\.value)
  }

  /// The input a value names, when the value is exactly one `inputs.` reference.
  private static func inputReference(in value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("${{"), trimmed.hasSuffix("}}") else { return nil }
    let inner = trimmed.dropFirst(3).dropLast(2).trimmingCharacters(in: .whitespaces)
    guard inner.hasPrefix("inputs.") else { return nil }
    let name = inner.dropFirst("inputs.".count)
    guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
      return nil
    }
    return String(name)
  }

  private func yq<T: Decodable>(_ expression: String, as type: T.Type) throws -> T {
    guard FileManager.default.isReadableFile(atPath: path) else {
      throw WorkflowError.workflowNotFound(path)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["yq", "-o=json", expression, path]

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    do {
      try process.run()
    } catch {
      throw GeneratorError.toolNotFound("yq")
    }
    let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw WorkflowError.yqFailed(
        expression: expression,
        standardError: String(decoding: errorData, as: UTF8.self)
      )
    }
    return try JSONDecoder().decode(T.self, from: outputData)
  }

  private struct InputDeclaration: Decodable {
    var `default`: ActionsScalar?
  }
}

/// A YAML scalar as the string Actions would put in the environment: a boolean
/// input reaches a script as "true" or "false", and a number as its digits.
struct ActionsScalar: Decodable {
  let value: String

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      value = string
    } else if let boolean = try? container.decode(Bool.self) {
      value = boolean ? "true" : "false"
    } else if let integer = try? container.decode(Int.self) {
      value = String(integer)
    } else if let number = try? container.decode(Double.self) {
      value = String(number)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Not a scalar an Actions environment variable can carry"
      )
    }
  }
}

public enum WorkflowError: Error, CustomStringConvertible {
  case workflowNotFound(String)
  case noGenerateStep(workflow: String)
  case yqFailed(expression: String, standardError: String)
  case unknownInput(workflow: String, key: String, input: String)
  case unresolvedExpression(workflow: String, key: String, value: String)

  public var description: String {
    switch self {
    case .workflowNotFound(let path):
      return "Workflow not found at \(path)"
    case .noGenerateStep(let workflow):
      return "\(workflow).yml has no step with id 'generate'"
    case .yqFailed(let expression, let standardError):
      return "yq failed for \(expression): \(standardError)"
    case .unknownInput(let workflow, let key, let input):
      return "\(workflow).yml sets \(key) from inputs.\(input), which it does not declare"
    case .unresolvedExpression(let workflow, let key, let value):
      return """
        \(workflow).yml sets \(key) to an expression these tests cannot resolve: \(value). \
        Teach EntryPoint.environment() what it means.
        """
    }
  }
}

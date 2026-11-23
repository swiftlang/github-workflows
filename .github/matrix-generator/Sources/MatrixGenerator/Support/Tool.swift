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

let jq = Tool("jq")

let yq = Tool("yq")

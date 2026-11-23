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

/// Generates the job matrix the rest of the workflow runs: the workflow's inputs in
/// as environment variables, the matrix out on standard output.
///
/// yq reads the YAML an input is written in and writes the YAML the matrix comes out
/// as, and jq writes the JSON form. Everything between them is typed.
public enum GenerateMatrix {
  public static func run() {
    // Populates the configuration from the environment, through the `@Input` initializers.
    let configuration = Configuration()

    guard let mode = Matrix.Mode(rawValue: configuration.matrixMode) else {
      fatal("MATRIX_MODE must be 'jobs' or 'toolchains', got '\(configuration.matrixMode)'")
    }
    guard let format = Matrix.Format(rawValue: configuration.matrixFormat) else {
      fatal("MATRIX_FORMAT must be 'yaml' or 'json', got '\(configuration.matrixFormat)'")
    }
    configuration.validatePairings(in: mode)

    let generator = Generator(configuration, mode: mode)
    let jobMatrix = generator.generate()

    print(jobMatrix.encoded(as: format), terminator: "")
  }
}

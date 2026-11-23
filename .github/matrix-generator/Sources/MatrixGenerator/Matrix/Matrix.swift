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

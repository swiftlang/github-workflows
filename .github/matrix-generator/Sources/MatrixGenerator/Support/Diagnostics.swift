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

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

#if canImport(FoundationNetworking)
// FoundationNetworking is a separate module in swift-foundation but not swift-corelibs-foundation.
import FoundationNetworking
#endif

#if canImport(WinSDK)
import WinSDK
#endif

struct GenericError: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}

/// Escape the given command to be printed for log output.
func escapeCommand(_ executable: URL, _ arguments: [String]) -> String {
  return ([executable.path] + arguments).map {
    if $0.contains(" ") {
      return "'\($0)'"
    }
    return $0
  }.joined(separator: " ")
}

/// Launch a subprocess with the given command and wait for it to finish
func run(_ executable: URL, _ arguments: String..., workingDirectory: URL? = nil) throws {
  print("Running \(escapeCommand(executable, arguments)) (working directory: \(workingDirectory?.path ?? "<nil>"))")
  let process = Process()
  process.executableURL = executable
  process.arguments = arguments
  if let workingDirectory {
    process.currentDirectoryURL = workingDirectory
  }

  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw GenericError(
      "\(escapeCommand(executable, arguments)) failed with non-zero exit code: \(process.terminationStatus)"
    )
  }
}

/// Find the executable with the given name in PATH.
public func lookup(executable: String) throws -> URL {
  #if os(Windows)
  let pathSeparator: Character = ";"
  let executable = executable + ".exe"
  #else
  let pathSeparator: Character = ":"
  #endif
  for pathVariable in ["PATH", "Path"] {
    guard let pathString = ProcessInfo.processInfo.environment[pathVariable] else {
      continue
    }
    for searchPath in pathString.split(separator: pathSeparator) {
      let candidateUrl = URL(fileURLWithPath: String(searchPath)).appendingPathComponent(executable)
      if FileManager.default.isExecutableFile(atPath: candidateUrl.path) {
        return candidateUrl
      }
    }
  }
  throw GenericError("Did not find \(executable)")
}

func downloadData(from url: URL) async throws -> Data {
  return try await withCheckedThrowingContinuation { continuation in
    URLSession.shared.dataTask(with: url) { data, _, error in
      if let error {
        continuation.resume(throwing: error)
        return
      }
      guard let data else {
        continuation.resume(throwing: GenericError("Received no data for \(url)"))
        return
      }
      continuation.resume(returning: data)
    }
    .resume()
  }
}

/// The JSON fields of the `https://api.github.com/repos/<repository>/pulls/<prNumber>` endpoint that we care about.
struct PRInfo: Codable {
  struct Base: Codable {
    /// The name of the PR's base branch.
    let ref: String
  }
  /// The base branch of the PR
  let base: Base

  /// The PR's description.
  let body: String?
}

/// - Parameters:
///   - repository: The repository's name, eg. `swiftlang/swift-syntax`
func getPRInfo(repository: String, prNumber: String) async throws -> PRInfo {
  guard let prInfoUrl = URL(string: "https://api.github.com/repos/\(repository)/pulls/\(prNumber)") else {
    throw GenericError("Failed to form URL for GitHub API")
  }

  do {
    let data = try await downloadData(from: prInfoUrl)
    return try JSONDecoder().decode(PRInfo.self, from: data)
  } catch {
    throw GenericError("Failed to load PR info from \(prInfoUrl): \(error)")
  }
}

/// Information about a PR that should be tested with this PR.
struct CrossRepoPR {
  /// The owner of the repository, eg. `swiftlang`
  let repositoryOwner: String

  /// The name of the repository, eg. `swift-syntax`
  let repositoryName: String

  /// The PR number that's referenced.
  let prNumber: String
}

/// Retrieve all PRs that are referenced from PR `prNumber` in `repository`.
/// `repository` is the owner and repo name joined by `/`, eg. `swiftlang/swift-syntax`.
func getCrossRepoPrs(repository: String, prNumber: String) async throws -> [CrossRepoPR] {
  var result: [CrossRepoPR] = []
  let prInfo = try await getPRInfo(repository: repository, prNumber: prNumber)
  for line in prInfo.body?.split(separator: "\n") ?? [] {
    guard line.lowercased().starts(with: "linked pr:") else {
      continue
    }
    // We can't use Swift's Regex here because this script needs to run on Windows with Swift 5.9, which doesn't support
    // Swift Regex.
    var remainder = line[...]
    guard let ownerRange = remainder.firstRange(of: "swiftlang/") ?? remainder.firstRange(of: "apple/") else {
      continue
    }
    let repositoryOwner = remainder[ownerRange].dropLast()
    remainder = remainder[ownerRange.upperBound...]
    let repositoryName = remainder.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    if repositoryName.isEmpty {
      continue
    }
    remainder = remainder.dropFirst(repositoryName.count)
    if remainder.starts(with: "/pull/") {
      remainder = remainder.dropFirst(6)
    } else if remainder.starts(with: "#") {
      remainder = remainder.dropFirst()
    } else {
      continue
    }
    let pullRequestNum = remainder.prefix { $0.isNumber }
    if pullRequestNum.isEmpty {
      continue
    }
    result.append(
      CrossRepoPR(
        repositoryOwner: String(repositoryOwner),
        repositoryName: String(repositoryName),
        prNumber: String(pullRequestNum)
      )
    )
  }
  return result
}

func main() async throws {
  guard ProcessInfo.processInfo.arguments.count >= 3 else {
    throw GenericError(
      """
      Expected two arguments:
      - Repository name, eg. `swiftlang/swift-syntax
      - PR number
      """
    )
  }
  let repository = ProcessInfo.processInfo.arguments[1]
  let prNumber = ProcessInfo.processInfo.arguments[2]

  let crossRepoPrs = try await getCrossRepoPrs(repository: repository, prNumber: prNumber)
  if !crossRepoPrs.isEmpty {
    print("Detected cross-repo PRs")
    for crossRepoPr in crossRepoPrs {
      print(" - \(crossRepoPr.repositoryOwner)/\(crossRepoPr.repositoryName)#\(crossRepoPr.prNumber)")
    }
  }

  for crossRepoPr in crossRepoPrs {
    let git = try lookup(executable: "git")
    let swift = try lookup(executable: "swift")
    let baseBranch = try await getPRInfo(
      repository: "\(crossRepoPr.repositoryOwner)/\(crossRepoPr.repositoryName)",
      prNumber: crossRepoPr.prNumber
    ).base.ref

    let workspaceDir = URL(fileURLWithPath: "..").resolvingSymlinksInPath()
    let repoDir = workspaceDir.appendingPathComponent(crossRepoPr.repositoryName)
    try run(
      git,
      "clone",
      "https://github.com/\(crossRepoPr.repositoryOwner)/\(crossRepoPr.repositoryName).git",
      "\(crossRepoPr.repositoryName)",
      workingDirectory: workspaceDir
    )
    try run(git, "fetch", "origin", "pull/\(crossRepoPr.prNumber)/merge:pr_merge", workingDirectory: repoDir)
    try run(git, "checkout", baseBranch, workingDirectory: repoDir)
    try run(git, "reset", "--hard", "pr_merge", workingDirectory: repoDir)
    try run(
      swift,
      "package",
      "config",
      "set-mirror",
      "--package-url",
      "https://github.com/\(crossRepoPr.repositoryOwner)/\(crossRepoPr.repositoryName).git",
      "--mirror-url",
      repoDir.path
    )
  }
}

do {
  try await main()
} catch {
  print(error)
  #if os(Windows)
  _Exit(1)
  #else
  exit(1)
  #endif
}

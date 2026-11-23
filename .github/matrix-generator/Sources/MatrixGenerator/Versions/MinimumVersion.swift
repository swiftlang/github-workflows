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

/// The oldest toolchain the package builds on. A version below it cannot resolve the
/// manifest, so a job on it fails for a reason the caller did not ask about.
struct MinimumVersion {
  /// As the caller or the manifest wrote it, for the message.
  let text: String
  private let floor: SwiftVersion?
  private let releases: SwiftReleases

  init(_ text: String, releases: SwiftReleases) {
    self.text = text
    self.releases = releases
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
    // The floor is the minor release, not the patch: a `6.2` label must satisfy a `6.2.3` minimum.
    self.floor = SwiftVersion(majorMinor: "\(version.major).\(version.minor)")
  }

  /// A nightly is always kept: it is not a released version this can order.
  func admits(_ label: String) -> Bool {
    guard let floor = self.floor else { return true }
    if VersionLabel(label).isNightly { return true }
    return self.releases.ordered(label) >= floor
  }

  /// What a caller does about a version the filter dropped. The filter is not an input of its
  /// own, so a message naming only what was dropped leaves them looking for a knob that isn't
  /// there.
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
      self.init(configuration.minimumSwiftVersion, releases: configuration.releases)
      return
    }
    let detected = MinimumVersion.detected(
      in: configuration.packagePath.isEmpty ? "." : configuration.packagePath,
      includingSubdirectories: configuration.searchSubdirectories
    )
    if !detected.isEmpty { log("Auto-detected minimum Swift tools version: \(detected)") }
    self.init(detected, releases: configuration.releases)
  }

  /// The lowest tools version the manifests in `root` declare, which is the oldest toolchain the
  /// package claims to build on.
  static func detected(in root: String, includingSubdirectories: Bool) -> String {
    let fileManager = FileManager.default

    // A directory that cannot be read would count as having no manifests, and a package
    // without one raises no floor, so a too-old Swift version would pass the filter.
    func contents(of directory: String) -> [String] {
      do {
        return try fileManager.contentsOfDirectory(atPath: directory)
      } catch {
        fatal("Could not read \(directory) to look for Package.swift manifests: \(error)")
      }
    }

    func manifests(in directory: String) -> [String] {
      let contents = contents(of: directory)
      let versioned = contents.filter { $0.hasPrefix("Package@swift-") && $0.hasSuffix(".swift") }.sorted()
      return (["Package.swift"] + versioned).map { directory == "." ? $0 : "\(directory)/\($0)" }
    }

    var directories = [root]
    if includingSubdirectories {
      directories += contents(of: root).filter { entry in
        var isDirectory: ObjCBool = false
        let path = root == "." ? entry : "\(root)/\(entry)"
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
      }.sorted().map { "\(root)/\($0)" }
    }

    var minimum: (version: SwiftVersion, text: String)?
    for path in directories.flatMap(manifests(in:)) {
      guard let declared = MinimumVersion.toolsVersion(ofManifestAt: path) else { continue }
      log("Found \(path) with tools-version: \(declared)")
      let version = SwiftVersion.inVersionList(declared)
      if let lowestSoFar = minimum, lowestSoFar.version <= version { continue }
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

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

/// A platform built and tested through xcodebuild. It is a step inside a macOS job rather
/// than a job of its own.
struct XcodeTarget: Encodable {
  var platform: String
  var scheme: String
  var buildDestination: String
  var testDestination: String
  var build: Bool
  var test: Bool

  enum CodingKeys: String, CodingKey {
    case platform, scheme, build, test
    case buildDestination = "build_destination"
    case testDestination = "test_destination"
  }

  /// The destinations a target takes when it names none of its own.
  ///
  /// These name the newest device of each kind, which ages with every Xcode release, so a
  /// target can give its own instead.
  static let destinations: [String: (build: String, test: String)] = [
    "macOS": (build: "generic/platform=macos,variant=macos", test: "name=My Mac,variant=macos"),
    "Catalyst": (
      build: "generic/platform=macos,variant=Mac Catalyst", test: "name=My Mac,variant=Mac Catalyst"
    ),
    "iOS": (build: "generic/platform=ios", test: "name=iPhone Air"),
    "watchOS": (build: "generic/platform=watchos", test: "name=Apple Watch Ultra 3 (49mm)"),
    "tvOS": (build: "generic/platform=tvos", test: "name=Apple TV 4K (3rd generation)"),
    "visionOS": (build: "generic/platform=visionos", test: "name=Apple Vision Pro"),
  ]
}

extension XcodeTarget {
  /// The platforms to build and test through xcodebuild, carried by every macOS entry: a map
  /// of platform to that target's settings, or a list of platforms taking the defaults.
  ///
  /// Reading them runs yq over what the caller wrote.
  static func list(in configuration: Configuration) -> [XcodeTarget] {
    let text = configuration.xcodeTargets
    if text.isEmpty { return [] }
    // A scalar is rejected rather than read as one platform: the parse is here only to tell a
    // map from a list, and the keys it yields have to match one in `destinations`, so YAML
    // rewriting one cannot pass unnoticed.
    guard let parsed = Parsed(text) else {
      fatal("xcode_targets is not valid JSON or YAML: \(text)")
    }
    guard parsed.isCollection else {
      fatal(
        """
        xcode_targets takes a map, such as {iOS: {build: true}}, or a list, such as [iOS, watchOS], \
        but got: \(text)
        """
      )
    }

    // A list asks for each platform with every setting left at its default.
    var members = parsed.mapMembers.map { (platform: $0.key, settings: $0.value) }
    if let listed = parsed.value.asArray {
      guard listed.allSatisfy({ $0.asString != nil }) else {
        fatal("xcode_targets as a list takes platform names, such as [iOS, watchOS], but got: \(text)")
      }
      members = listed.map { (platform: $0.text, settings: JSONValue.object([:])) }
    }

    return members.map { platform, value in
      guard let defaults = XcodeTarget.destinations[platform] else {
        fatal(
          """
          xcode_targets names an unknown platform '\(platform)'; the platforms are macOS, Catalyst, iOS, \
          watchOS, tvOS and visionOS.
          """
        )
      }
      // A platform named with no settings is written `iOS:`, which parses as null.
      guard case .object(let settings) = (value.isNull ? .object([:]) : value) else {
        fatal(
          "xcode_targets settings for \(platform) take the form {build: true, test: true}, but got: \(value)"
        )
      }
      // A misspelled setting would otherwise be dropped and its default left in place: a
      // target carrying `sheme` would build the default scheme, or fail for lack of one.
      let unknown = Set(settings.keys)
        .subtracting(["build", "test", "scheme", "build_destination", "test_destination"]).sorted()
      guard unknown.isEmpty else {
        fatal(
          """
          xcode_targets settings for \(platform) include unknown keys: \(unknown.joined(separator: ", ")). \
          A target takes build, test, scheme, build_destination and test_destination.
          """
        )
      }

      func flag(_ key: String, or fallback: Bool) -> Bool {
        guard let setting = settings[key]?.nonNull else { return fallback }
        guard let value = setting.asBool else {
          fatal(
            "xcode_targets settings for \(platform) take build and test as true or false, but got: \(value)"
          )
        }
        return value
      }
      // Building is the default because a package can be built for every platform, while
      // testing needs a simulator and takes far longer.
      let build = flag("build", or: true)
      let test = flag("test", or: false)
      guard build || test else {
        fatal(
          "xcode_targets asks for \(platform) with build and test both false, so the target would do nothing."
        )
      }

      let scheme = settings["scheme"]?.text ?? configuration.xcodeScheme
      if scheme.isEmpty {
        fatal(
          """
          xcode_targets names \(platform) but no scheme reaches it; set xcode_scheme, or give the target \
          its own. xcodebuild builds nothing without a scheme.
          """
        )
      }

      return XcodeTarget(
        platform: platform,
        scheme: scheme,
        buildDestination: settings["build_destination"]?.text ?? defaults.build,
        testDestination: settings["test_destination"]?.text ?? defaults.test,
        build: build,
        test: test
      )
    }
  }
}

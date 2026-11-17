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

/// A Swift SDK build: the SDK its entries build against, and the inputs that configure them,
/// which all share one prefix.
struct SDKBuild {
  /// The prefix every one of its inputs shares.
  let prefix: String
  let kind: MatrixEntry.SwiftBuild.SDK.Kind
  /// What its job names lead with.
  let name: String

  let enabled: Bool
  let versions: [String]
  let commands: Commands
  let setupCommand: String
  let overrides: VersionOverrides

  init(prefix: String, kind: MatrixEntry.SwiftBuild.SDK.Kind, name: String) {
    self.prefix = prefix
    self.kind = kind
    self.name = name
    let variable = prefix.uppercased()
    self.enabled = Input.read("ENABLE_\(variable)_BUILD", default: true)
    self.versions = Input.read("\(variable)_VERSIONS", default: Configuration.defaultSDKVersions)
    self.commands = Input.read("\(variable)_COMMAND", default: "swift build")
    self.setupCommand = Input.read("\(variable)_SETUP_COMMAND", default: "")
    self.overrides = Input.read("\(variable)_VERSION_OVERRIDES", default: VersionOverrides())
  }

  /// The input that turns this build on.
  var enableInput: String { "enable_\(self.prefix)_build" }
  /// The input naming the Swift versions it builds on.
  var versionsInput: String { "\(self.prefix)_versions" }
  /// The input naming what it runs.
  var commandInput: String { "\(self.prefix)_command" }
}

#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2024 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

set -euo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

log "Editing Package.swift..."
cat <<EOF >> "Package.swift"
package.dependencies.append(
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", "1.0.0"..<"1.4.0")
)
EOF

log "Checking documentation targets..."
for target in $(yq -r '.builder.configs[].documentation_targets[]' .spi.yml); do
  log "Checking target $target..."
  swift package plugin generate-documentation --target "$target" --warnings-as-errors --analyze --level detailed
done

log "✅ Found no documentation issues."

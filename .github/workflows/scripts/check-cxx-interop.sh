#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2026 Apple Inc. and the Swift project authors
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

log "Checking for Cxx interoperability compatibility..."

source_dir=$(pwd)
working_dir=$(mktemp -d "/tmp/tmp_swift_package_XXXXXXXXXX")
project_name=$(basename "$working_dir")
source_file="Sources/$project_name/$project_name.swift"
library_products=$(swift package dump-package | jq -r '.products[] | select(.type.library != null) | .name')
package_name=$(swift package dump-package | jq -r '.name')

# The check works by importing the library products from a package built in Cxx
# interoperability mode. With none to import it would build an empty package and
# report success for a check it never ran.
if [ -z "$library_products" ]; then
  fatal "No library products in $package_name, so there is nothing to import in Cxx interoperability mode."
fi

cd "$working_dir"
swift package init

{
  echo 'let swiftSettings: [SwiftSetting] = [.interoperabilityMode(.Cxx)]'
  echo 'for target in package.targets { target.swiftSettings = (target.swiftSettings ?? []) + swiftSettings }'
} >> Package.swift

echo "package.dependencies.append(.package(path: \"$source_dir\"))" >> Package.swift
echo >> "$source_file"

for product in $library_products; do
  echo "package.targets.first!.dependencies.append(.product(name: \"$product\", package: \"$package_name\"))" >> Package.swift
  echo "import $product" >> "$source_file"
done

# The matrix entry's command arguments arrive here, so swift_flags and per-version
# overrides reach the compiler that does the interoperability build.
swift build "$@"

log "Passed the Cxx interoperability tests."

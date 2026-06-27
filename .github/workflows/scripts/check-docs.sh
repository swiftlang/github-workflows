#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2025 Apple Inc. and the Swift project authors
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

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --no-analyze                                  Do not pass --analyze to 'swift package plugin generate-documentation'.
  --doc-targets target [target2 ...]            The documentation targets to build.
  --additional-docc-arguments [arg ...]         Extra arguments forwarded to 'swift package plugin generate-documentation'.
  -h, --help                                    Show this help message.
EOF
}

is_known_option() {
  case "$1" in
    --no-analyze|--additional-docc-arguments|--doc-targets|-h|--help)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

analyze_flag="--analyze"
additional_docc_arguments=""
docs_targets=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-analyze)
      analyze_flag=""
      shift
      ;;
    --doc-targets)
      shift
      collected=()
      while [[ $# -gt 0 ]] && ! is_known_option "$1"; do
        collected+=("$1")
        shift
      done
      docs_targets="${collected[*]}"
      ;;
    --additional-docc-arguments)
      shift
      collected=()
      while [[ $# -gt 0 ]] && ! is_known_option "$1"; do
        collected+=("$1")
        shift
      done
      additional_docc_arguments="${collected[*]}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "${docs_targets}" ] ; then
  if [ ! -f .spi.yml ]; then
    log "No '.spi.yml' found in \"$(pwd)\", no documentation targets to check."
    exit 0
  fi
fi

if ! command -v yq &> /dev/null; then
  case "$(uname -s)" in
  Darwin*) brew install yq;;
  Linux*) apt -q update && apt -yq install yq;;
  esac
fi

if [ -z "${docs_targets}" ] ; then
  docs_targets=$(yq -r ".builder.configs[] | select(.documentation_targets[] != \"\") | .documentation_targets[]" .spi.yml)
fi

package_files=$(find . -maxdepth 1 -name 'Package*.swift')
if [ -z "$package_files" ]; then
  fatal "Package.swift not found in \"$(pwd)\". Please ensure you are running this script from the root of a Swift package."
fi

# yq 3.1.0-3 doesn't have filter, otherwise we could replace the grep call with "filter(.identity == "swift-docc-plugin") | keys | .[]"
hasDoccPlugin=$(swift package dump-package | yq -r '.dependencies[].sourceControl' | grep -e "\"identity\": \"swift-docc-plugin\"" || true)
if [[ -n $hasDoccPlugin ]]
then
    log "swift-docc-plugin already exists"
else
    log "Appending swift-docc-plugin"
    for package_file in $package_files; do
      log "Editing $package_file..."
      cat <<EOF >> "$package_file"

package.dependencies.append(
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0")
)
EOF
    done
fi

log "Checking documentation targets..."
for target in ${docs_targets}; do
  log "Checking target $target..."
  # shellcheck disable=SC2086 # We explicitly want to explode "$analyze_flag"  an "$additional_docc_arguments"d into multiple arguments.
  swift package plugin generate-documentation --target "$target" --warnings-as-errors $analyze_flag $additional_docc_arguments
done

log "✅ Found no documentation issues."

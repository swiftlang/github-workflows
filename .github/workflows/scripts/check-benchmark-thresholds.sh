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

set -uo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

if [ -z "${SWIFT_VERSION:-}" ]; then
  fatal "SWIFT_VERSION must be specified."
fi

swift_version="$SWIFT_VERSION"

# Any arguments to this script are passed through to SwiftPM.
swift_package_arguments=("$@")

# bash 3.2, which is what macOS runners provide, treats "${array[@]}" on an empty
# array as an unbound variable under `set -u`, so the expansion is guarded. The
# arguments are empty by default, and macOS benchmarks run on that default.
swift_package() {
  local package_path="$1"
  shift
  swift package --package-path "$package_path" ${swift_package_arguments[@]+"${swift_package_arguments[@]}"} "$@"
}

# BENCHMARK_PACKAGE_PATHS is a JSON array of strings or a newline-separated
# list. It takes precedence over the singular BENCHMARK_PACKAGE_PATH, which
# remains supported so a caller naming one path needs nothing else.
plural_paths="${BENCHMARK_PACKAGE_PATHS:-}"
singular_path="${BENCHMARK_PACKAGE_PATH:-.}"

# Recognize an empty array without jq: the workflow passes "[]" when a caller
# named no paths, and the container images do not carry jq.
trimmed="${plural_paths#"${plural_paths%%[![:space:]]*}"}"
trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
if [[ "$trimmed" == "[]" ]]; then
  trimmed=""
  plural_paths=""
fi

if [[ "$trimmed" == \[* ]]; then
  command -v jq >/dev/null 2>&1 || fatal "BENCHMARK_PACKAGE_PATHS is a JSON array but jq is not installed. Install it in the pre-build command, or pass BENCHMARK_PACKAGE_PATH instead."
  jq empty <<< "$plural_paths" 2>/dev/null || fatal "BENCHMARK_PACKAGE_PATHS is not valid JSON."
  jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null <<< "$plural_paths" \
    || fatal "BENCHMARK_PACKAGE_PATHS must be a JSON array of strings."
  if [[ "$(jq 'length' <<< "$plural_paths")" == "0" ]]; then
    benchmark_package_paths="$singular_path"
  else
    benchmark_package_paths=$(jq -r '.[]' <<< "$plural_paths")
  fi
elif [[ -n "$plural_paths" ]]; then
  benchmark_package_paths="$plural_paths"
else
  benchmark_package_paths="$singular_path"
fi

run_one() {
  local benchmark_package_path="$1"

  swift_package "$benchmark_package_path" benchmark thresholds check --format metricP90AbsoluteThresholds --path "${benchmark_package_path}/Thresholds/${swift_version}/"
  local rc="$?"

  # The measurements are within their thresholds, so there is nothing to recalculate.
  if [[ "$rc" == 0 ]]; then
    return 0
  fi

  # A non-zero exit from 'thresholds check' means either that thresholds
  # regressed or that the build failed. Try 'thresholds update' to tell them
  # apart: if that also fails it was a build error.
  log "Recalculating thresholds for ${benchmark_package_path}..."

  swift_package "$benchmark_package_path" benchmark thresholds update --format metricP90AbsoluteThresholds --path "${benchmark_package_path}/Thresholds/${swift_version}/"
  local update_rc="$?"

  if [[ "$update_rc" != 0 ]]; then
    error "Benchmark in ${benchmark_package_path} failed to run due to build error."
    return "$update_rc"
  fi

  # Use echo, not log, so the diff is clean for tooling that scrapes it out of
  # the job log. The marker carries the package path, so a multi-package run's
  # diffs can be told apart.
  echo "=== BEGIN DIFF (${benchmark_package_path}) ==="
  git add --intent-to-add "${benchmark_package_path}/Thresholds/"
  git diff HEAD -- "${benchmark_package_path}/Thresholds/"
  return 1
}

overall_rc=0
failed=()
while IFS= read -r path; do
  [ -z "$path" ] && continue
  echo "::group::Running benchmarks for $path"
  run_one "$path"
  rc=$?
  echo "::endgroup::"
  if [[ "$rc" -ne 0 ]]; then
    overall_rc=$rc
    failed+=("$path")
  fi
done <<< "$benchmark_package_paths"

if [[ "$overall_rc" -ne 0 ]]; then
  echo "::error::Benchmark failures in: ${failed[*]}"
fi
exit "$overall_rc"

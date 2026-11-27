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
# list. Empty means the current directory.
plural_paths="${BENCHMARK_PACKAGE_PATHS:-}"

# Recognize an empty array without jq: the workflow passes "[]" when a caller
# named no paths, and the container images do not carry jq.
trimmed="${plural_paths#"${plural_paths%%[![:space:]]*}"}"
trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
if [[ "$trimmed" == "[]" ]]; then
  trimmed=""
  plural_paths=""
fi

if [[ "$trimmed" == \[* ]]; then
  command -v jq >/dev/null 2>&1 || fatal "BENCHMARK_PACKAGE_PATHS is a JSON array but jq is not installed. Install it in the pre-build command, or pass a newline-separated list instead."
  jq empty <<< "$plural_paths" 2>/dev/null || fatal "BENCHMARK_PACKAGE_PATHS is not valid JSON."
  jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null <<< "$plural_paths" \
    || fatal "BENCHMARK_PACKAGE_PATHS must be a JSON array of strings."
  if [[ "$(jq 'length' <<< "$plural_paths")" == "0" ]]; then
    benchmark_package_paths="."
  else
    benchmark_package_paths=$(jq -r '.[]' <<< "$plural_paths")
  fi
elif [[ -n "$plural_paths" ]]; then
  benchmark_package_paths="$plural_paths"
else
  benchmark_package_paths="."
fi

# The benchmark plugin redraws a progress bar on every update, and a CI log keeps each
# redraw as a line of its own: thousands of lines that bury the results.
drop_progress_lines() {
  grep --line-buffered -v 'ETA: ' || true
}

# Runs the plugin with its progress bar removed, and returns the plugin's status
# rather than the filter's.
swift_package_quietly() {
  swift_package "$@" 2>&1 | drop_progress_lines
  return "${PIPESTATUS[0]}"
}

run_one() {
  local benchmark_package_path="$1"

  echo "::group::Check thresholds for ${benchmark_package_path}"
  swift_package_quietly "$benchmark_package_path" benchmark thresholds check --format metricP90AbsoluteThresholds --path "${benchmark_package_path}/Thresholds/${swift_version}/"
  local rc="$?"
  echo "::endgroup::"

  # The measurements are within their thresholds, so there is nothing to recalculate.
  if [[ "$rc" == 0 ]]; then
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      {
        echo "### Benchmarks in \`${benchmark_package_path}\` (Swift ${swift_version})"
        echo
        echo "All measurements are within their thresholds."
        echo
      } >>"$GITHUB_STEP_SUMMARY"
    fi
    return 0
  fi

  # A non-zero exit from 'thresholds check' means either that thresholds
  # regressed or that the build failed. Try 'thresholds update' to tell them
  # apart: if that also fails it was a build error.
  log "Recalculating thresholds for ${benchmark_package_path}..."

  local update_output
  update_output=$(mktemp)
  echo "::group::Recalculate thresholds for ${benchmark_package_path}"
  swift_package_quietly "$benchmark_package_path" benchmark thresholds update --format metricP90AbsoluteThresholds --path "${benchmark_package_path}/Thresholds/${swift_version}/" | tee "$update_output"
  local update_rc="${PIPESTATUS[0]}"
  echo "::endgroup::"

  if [[ "$update_rc" != 0 ]]; then
    # The compiler's diagnostics are in the folded group; repeat the end of them where
    # a reader looking for the cause will see them.
    tail -n 40 "$update_output"
    rm -f "$update_output"
    error "Benchmark in ${benchmark_package_path} failed to run due to build error."
    return "$update_rc"
  fi

  rm -f "$update_output"

  git add --intent-to-add "${benchmark_package_path}/Thresholds/"

  local thresholds_diff
  thresholds_diff=$(git diff HEAD -- "${benchmark_package_path}/Thresholds/")

  # GitHub colors a fenced diff on the job's summary page, which shows what moved without
  # opening the log. -U0 leaves out the unchanged metrics around each change.
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### Benchmark thresholds that moved in \`${benchmark_package_path}\` (Swift ${swift_version})"
      echo
      echo '```diff'
      git diff -U0 HEAD -- "${benchmark_package_path}/Thresholds/"
      echo '```'
    } >>"$GITHUB_STEP_SUMMARY"
  fi

  # Use echo, not log, so the diff is clean for tooling that scrapes it out of
  # the job log. The marker carries the package path, so a multi-package run's
  # diffs can be told apart.
  echo "::group::Thresholds diff for ${benchmark_package_path}"
  echo "=== BEGIN DIFF (${benchmark_package_path}) ==="
  echo "$thresholds_diff"
  echo "::endgroup::"
  return 1
}

overall_rc=0
failed=()
while IFS= read -r path; do
  [ -z "$path" ] && continue
  run_one "$path"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    overall_rc=$rc
    failed+=("$path")
  fi
done <<< "$benchmark_package_paths"

if [[ "$overall_rc" -ne 0 ]]; then
  echo "::error::Benchmark failures in: ${failed[*]}"
fi
exit "$overall_rc"

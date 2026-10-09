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

# Tests how check-benchmark-thresholds.sh reads its package paths and what it makes of
# the benchmark plugin's exit status.
#
# A benchmark regression and a package that does not build both leave 'thresholds check'
# non-zero, and the script tells them apart by whether 'thresholds update' then
# succeeds. Reporting a build error as a regression sends an adopter to look at
# measurements that were never taken; reporting a regression as a build error hides it.
#
# swift is stubbed, so the tests take no measurements and need no toolchain: what is
# under test is the path list, the branch on exit status, and the loop over packages. The
# benchmark plugin's own behavior is not.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/workflows/scripts/check-benchmark-thresholds.sh"

failures=0

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

STUB_DIR="$WORKDIR/stubs"
mkdir -p "$STUB_DIR"

# A repository of its own: the diff the script produces runs git against the working
# tree, which must not be this checkout.
REPOSITORY="$WORKDIR/repository"
mkdir -p "$REPOSITORY/one/Thresholds/6.3" "$REPOSITORY/two/Thresholds/6.3"
git -C "$REPOSITORY" init --quiet
git -C "$REPOSITORY" -c user.email=ci@example.com -c user.name=CI commit --quiet --allow-empty -m "empty"

export STUB_INVOCATIONS="$WORKDIR/invocations.txt"

# Stands in for the benchmark plugin. STUB_CHECK_STATUS and STUB_UPDATE_STATUS are the
# statuses 'thresholds check' and 'thresholds update' report; a fresh threshold file
# stands in for what an update writes.
cat >"$STUB_DIR/swift" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_INVOCATIONS"
package_path=""
for ((index = 1; index <= $#; index++)); do
    if [[ "${!index}" == "--package-path" ]]; then
        next=$((index + 1))
        package_path="${!next}"
    fi
done
case "$*" in
    *"thresholds check"*)
        exit "${STUB_CHECK_STATUS:-0}"
        ;;
    *"thresholds update"*)
        if [[ "${STUB_UPDATE_STATUS:-0}" == "0" ]]; then
            printf '{"wallClock":100}\n' >"$package_path/Thresholds/6.3/Benchmark.p90.json"
        fi
        exit "${STUB_UPDATE_STATUS:-0}"
        ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/swift"

CHECK_LOG="$WORKDIR/check.log"

# run_check <check_status> <update_status> <paths_json> <path> [argument ...] - echoes the
# exit status; the log is left in $CHECK_LOG and the stub's invocations in
# $STUB_INVOCATIONS.
run_check() {
    local check_status="$1" update_status="$2" paths_json="$3" path="$4"
    shift 4
    : >"$STUB_INVOCATIONS"
    git -C "$REPOSITORY" checkout --quiet -- . 2>/dev/null
    git -C "$REPOSITORY" clean --quiet -fd
    (
        cd "$REPOSITORY" || exit 1
        PATH="$STUB_DIR:$PATH" \
        SWIFT_VERSION="6.3" \
        STUB_CHECK_STATUS="$check_status" \
        STUB_UPDATE_STATUS="$update_status" \
        BENCHMARK_PACKAGE_PATHS="$paths_json" \
        BENCHMARK_PACKAGE_PATH="$path" \
            "$SCRIPT" "$@" >"$CHECK_LOG" 2>&1
    )
    echo "$?"
}

assert_status() {
    local what="$1" expected="$2" actual="$3"
    if [[ "$expected" != "$actual" ]]; then
        echo "  FAIL $what: expected exit $expected, got $actual"
        failures=$((failures + 1))
    else
        echo "  ok   $what"
    fi
}

assert_contains() {
    local what="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  FAIL $what: [$needle] not found in [$haystack]"
        failures=$((failures + 1))
    else
        echo "  ok   $what"
    fi
}

assert_lacks() {
    local what="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  FAIL $what: [$needle] found in [$haystack]"
        failures=$((failures + 1))
    else
        echo "  ok   $what"
    fi
}

# The version labels the threshold files are keyed on, so a run without one would check
# a directory that does not exist.
missing_version_status=$(
    cd "$REPOSITORY" \
        && PATH="$STUB_DIR:$PATH" BENCHMARK_PACKAGE_PATH="one" "$SCRIPT" >"$CHECK_LOG" 2>&1
    echo "$?"
)
assert_status "a run without SWIFT_VERSION is refused" "1" "$missing_version_status"
assert_contains "the refusal names SWIFT_VERSION" "SWIFT_VERSION must be specified" \
    "$(cat "$CHECK_LOG")"

echo "== Package paths"

assert_status "measurements within their thresholds pass" "0" "$(run_check 0 0 "" "one")"
assert_contains "the named package is checked" "--package-path one" "$(cat "$STUB_INVOCATIONS")"
assert_lacks "nothing is recalculated" "thresholds update" "$(cat "$STUB_INVOCATIONS")"

assert_status "a JSON list of paths is accepted" "0" "$(run_check 0 0 '["one","two"]' ".")"
assert_contains "the first path is checked" "--package-path one" "$(cat "$STUB_INVOCATIONS")"
assert_contains "the second path is checked" "--package-path two" "$(cat "$STUB_INVOCATIONS")"
assert_lacks "the singular path is not also checked" "--package-path ." \
    "$(cat "$STUB_INVOCATIONS")"

assert_status "a newline-separated list of paths is accepted" "0" \
    "$(run_check 0 0 $'one\ntwo' ".")"
assert_contains "both paths are checked" "--package-path two" "$(cat "$STUB_INVOCATIONS")"

# The workflow passes "[]" when a caller named no paths. The container images carry no
# jq, so recognizing it must not need one: PATH holds the stubbed toolchain and nothing
# else.
: >"$STUB_INVOCATIONS"
empty_list_status=$(
    cd "$REPOSITORY" \
        && PATH="$STUB_DIR" SWIFT_VERSION="6.3" \
            BENCHMARK_PACKAGE_PATHS="[]" BENCHMARK_PACKAGE_PATH="one" \
            "$SCRIPT" >"$CHECK_LOG" 2>&1
    echo "$?"
)
assert_status "an empty JSON list falls back to the singular path, without jq" "0" \
    "$empty_list_status"
assert_contains "the singular path is checked" "--package-path one" "$(cat "$STUB_INVOCATIONS")"

assert_status "a JSON list that is not a list of strings is refused" "1" \
    "$(run_check 0 0 '[1,2]' ".")"
assert_contains "the refusal says what is wrong" "must be a JSON array of strings" \
    "$(cat "$CHECK_LOG")"

echo "== Swift package arguments"

assert_status "arguments are accepted" "0" "$(run_check 0 0 "" "one" --disable-sandbox)"
assert_contains "arguments reach the plugin" "--package-path one --disable-sandbox" \
    "$(cat "$STUB_INVOCATIONS")"

echo "== Regression and build error"

# A regression: the check fails, the update succeeds, and the diff says what moved.
assert_status "a regression fails the job" "1" "$(run_check 1 0 "" "one")"
assert_contains "the regression is recalculated" "thresholds update" "$(cat "$STUB_INVOCATIONS")"
assert_contains "the diff is printed" "=== BEGIN DIFF (one) ===" "$(cat "$CHECK_LOG")"
assert_contains "the diff holds the new threshold" "Benchmark.p90.json" "$(cat "$CHECK_LOG")"

# A build error: neither the check nor the update can run, so there is nothing to diff.
assert_status "a build error fails the job" "2" "$(run_check 1 2 "" "one")"
assert_contains "the build error is called one" "failed to run due to build error" \
    "$(cat "$CHECK_LOG")"
assert_lacks "no diff is printed for a build error" "BEGIN DIFF" "$(cat "$CHECK_LOG")"

echo "== Several packages"

# One package's regression must not stop the others being measured, and the summary has
# to name the one that failed.
assert_status "a regression in one of several packages fails the job" "1" \
    "$(run_check 1 0 '["one","two"]' ".")"
assert_contains "the other package is still checked" "--package-path two" \
    "$(cat "$STUB_INVOCATIONS")"
assert_contains "the summary names both failures" "Benchmark failures in: one two" \
    "$(cat "$CHECK_LOG")"

if [[ "$failures" -gt 0 ]]; then
    printf '\n%d failed\n' "$failures"
    exit 1
fi
printf '\nall passed\n'

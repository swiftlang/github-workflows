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

# Tests that matrix/job-runner-macos.sh propagates failure, runs the command in the
# setup command's shell, hands the entry's environment to it, and refuses an
# xcodebuild target that asks for work with nowhere to do it.
#
# A step reporting success for a command that failed is the worst kind of bug
# this repository can ship, because every adopter believes a green check.
#
# macOS only, and needs one real Xcode so `xcrun swift --version` can run. The
# script's Xcode lookup is pointed at a scratch directory holding a symlink,
# which is what XCODE_APPLICATIONS_DIRECTORY exists for.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${REPO_ROOT}/.github/workflows/scripts/matrix/job-runner-macos.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Skipping: job-runner-macos.sh needs macOS (this is $(uname -s))."
    exit 0
fi

# Any real Xcode will do; the tests never build, they only need xcrun and xcodebuild
# to answer.
real_xcode=""
for candidate in /Applications/Xcode*.app; do
    if [[ -d "$candidate/Contents/Developer" ]]; then
        real_xcode="$candidate"
        break
    fi
done
if [[ -z "$real_xcode" ]]; then
    echo "Skipping: no Xcode with a Contents/Developer found under /Applications."
    exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
XCODE_DIR="$WORKDIR/Applications"
mkdir -p "$XCODE_DIR"
ln -s "$real_xcode" "$XCODE_DIR/Xcode_swift_test.app"
mkdir -p "$WORKDIR/subpackage"
RUNNER_LOG="$WORKDIR/runner.log"

# Reports the environment the runner exported, as a matrix entry's command. Newlines
# in a value are shown as "/", so one line of the report holds one variable.
cat >"$WORKDIR/report-env.sh" <<'REPORT'
#!/bin/bash
{
    printf 'MULTILINE=%s\n' "$(printf '%s' "${MULTILINE_VALUE-unset}" | tr '\n' '/')"
    printf 'EMPTY=%s\n' "${EMPTY_VALUE-unset}"
} >env-report.txt
REPORT
chmod +x "$WORKDIR/report-env.sh"

failures=0

# run_matrix <setup_command> <command> [env_json] [xcode_targets_json]
# [xcode_debug_output] - echoes the exit status; the combined output is left in
# $RUNNER_LOG.
run_matrix() {
    local setup="$1" command="$2" env_json="${3:-}" targets="${4:-}" debug_output="${5:-false}"
    if [[ -z "$env_json" ]]; then
        env_json='{}'
    fi
    (
        cd "$WORKDIR" || exit 1
        XCODE_APPLICATIONS_DIRECTORY="$XCODE_DIR" \
        XCODE_TARGETS_JSON="$targets" \
        XCODE_DEBUG_OUTPUT="$debug_output" \
            "$RUNNER" "" "test" "$setup" "$command" "[]" "$env_json" "false" >"$RUNNER_LOG" 2>&1
        echo "$?"
    )
}

assert_status() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "ok - $description"
    else
        echo "FAILED - $description: expected exit $expected, got $actual"
        failures=$((failures + 1))
    fi
}

assert_text() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "ok - $description"
    else
        echo "FAILED - $description: expected [$expected], got [$actual]"
        failures=$((failures + 1))
    fi
}

assert_contains() {
    local description="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "ok - $description"
    else
        echo "FAILED - $description: [$needle] not found in [$haystack]"
        failures=$((failures + 1))
    fi
}

# A command that fails must fail the job; anything else reports a green check for
# work that did not pass.
assert_status "a failing command fails the job" "1" \
    "$(run_matrix "" "exit 1")"

assert_status "a succeeding command passes" "0" \
    "$(run_matrix "" "true")"

# A failing setup command must stop the run, otherwise the command executes
# against whatever state the half-finished setup left behind. The exact status is
# asserted, not just non-zero, since the runner is expected to propagate it.
assert_status "a failing setup command fails the job with its own status" "3" \
    "$(run_matrix "exit 3" "true")"

# The setup command and the command share a shell, so `cd` in setup carries over.
# Without this a caller entering a subdirectory silently tests the root package.
assert_status "the command runs in the setup command's directory" "0" \
    "$(run_matrix "cd subpackage" "test \"\$(basename \"\$PWD\")\" = subpackage")"

# Without a cd the command must run in the working directory; otherwise the
# previous assertion would pass even if the setup command's shell were discarded.
assert_status "without a cd the command runs in the working directory" "1" \
    "$(run_matrix "" "test \"\$(basename \"\$PWD\")\" = subpackage")"

# An entry's environment has to reach the command as written: a value from a YAML
# block scalar carries newlines, and one written empty is still a value.
env_json='{"MULTILINE_VALUE":"first\nsecond","EMPTY_VALUE":""}'
assert_status "an entry with a multi-line environment value runs" "0" \
    "$(run_matrix "" "$WORKDIR/report-env.sh" "$env_json")"
assert_text "a multi-line environment value arrives whole" "MULTILINE=first/second" \
    "$(grep '^MULTILINE=' "$WORKDIR/env-report.txt")"
assert_text "an empty environment value is still exported" "EMPTY=" \
    "$(grep '^EMPTY=' "$WORKDIR/env-report.txt")"

# A target asking for work with no destination to do it on must fail. Skipping it
# would report a green check for a platform that was never built or tested.
assert_status "a build target with no build_destination fails" "1" \
    "$(run_matrix "" "true" "" '[{"platform":"iOS","scheme":"Widget","build":true}]')"
assert_contains "the build failure names the platform and the missing field" \
    "iOS target has build: true but no build_destination" "$(cat "$RUNNER_LOG")"

# The same for a test with no test_destination. This target sets build: false, which
# the runner has to honor, or it fails on the missing build_destination instead.
assert_status "a test target with no test_destination fails" "1" \
    "$(run_matrix "" "true" "" '[{"platform":"watchOS","scheme":"Widget","build":false,"test":true}]')"
assert_contains "the test failure names the platform and the missing field" \
    "watchOS target has test: true but no test_destination" "$(cat "$RUNNER_LOG")"

# With debug output the -quiet argument is dropped, leaving an empty array that bash
# 3.2 refuses to expand under `set -u` unless it is guarded. xcodebuild then fails on
# the scratch directory, which is proof enough that it was reached with an argument
# list bash was willing to build.
build_target='[{"platform":"iOS","scheme":"Widget","build":true,"build_destination":"generic/platform=iOS"}]'
run_matrix "" "true" "" "$build_target" "true" >/dev/null
assert_contains "a target with debug output reaches xcodebuild" \
    "does not contain an Xcode project" "$(cat "$RUNNER_LOG")"

echo
if [[ "$failures" -eq 0 ]]; then
    echo "All macOS runner tests passed."
    exit 0
fi
echo "$failures macOS runner test(s) failed."
exit 1

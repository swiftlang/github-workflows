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

# Tests that matrix/job-runner-linux.sh propagates failure, hands a matrix entry's
# environment and build command to what it runs, and refuses an entry whose fields
# contradict each other. It also tests that install-and-build-with-sdk.sh, which the
# runner invokes for an SDK entry, refuses an Android build whose triples are missing
# or empty, and survives an unset ANDROID_NDK_HOME.
#
# A step reporting success for a command that failed is the worst kind of bug this
# repository can ship, because every adopter believes a green check.
#
# The toolchain install is skipped and swiftly, docker and the SDK script are stubbed,
# so the tests need no Swift, no Docker daemon and no network, and run on any platform.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${REPO_ROOT}/.github/workflows/scripts/matrix/job-runner-linux.sh"

failures=0

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/subpackage"

RUNNER_LOG="$WORKDIR/runner.log"
STUB_DIR="$WORKDIR/stubs"
SCRIPTS_DIR="$WORKDIR/scripts"
SWIFTLY_HOME="$WORKDIR/swiftly"
mkdir -p "$STUB_DIR" "$SCRIPTS_DIR" "$SWIFTLY_HOME"

# `swiftly` on PATH is what makes the installer return instead of fetching a Linux
# tarball, and it then sources env.sh from SWIFTLY_HOME_DIR.
printf '#!/bin/bash\nexit 0\n' >"$STUB_DIR/swiftly"
: >"$SWIFTLY_HOME/env.sh"

# docker and the SDK script record their arguments, one per line, so the tests can
# assert on what the runner asked for. An argument holding a newline spans two lines,
# which assert_contains still recognizes.
cat >"$STUB_DIR/docker" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >>docker-args.txt
STUB
cat >"$SCRIPTS_DIR/install-and-build-with-sdk.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >>sdk-args.txt
STUB

# Reports the environment the runner exported, as a matrix entry's command. Newlines
# in a value are shown as "/", so one line of the report holds one variable.
cat >"$WORKDIR/report-env.sh" <<'REPORT'
#!/bin/bash
{
    printf 'MULTILINE=%s\n' "$(printf '%s' "${MULTILINE_VALUE-unset}" | tr '\n' '/')"
    printf 'EMPTY=%s\n' "${EMPTY_VALUE-unset}"
} >env-report.txt
REPORT

chmod +x "$STUB_DIR/swiftly" "$STUB_DIR/docker" \
    "$SCRIPTS_DIR/install-and-build-with-sdk.sh" "$WORKDIR/report-env.sh"

# drive_runner <setup_command> <command> <env_json> <sdk_json> [container_json] -
# echoes the exit status; the combined output is left in $RUNNER_LOG.
drive_runner() {
    (
        cd "$WORKDIR" || exit 1
        export CONTAINER_JSON="${5:-null}"
        PATH="$STUB_DIR:$PATH" \
        SWIFTLY_HOME_DIR="$SWIFTLY_HOME" \
        SCRIPTS_ROOT="$SCRIPTS_DIR" \
        SKIP_SWIFT_INSTALL=true \
            "$RUNNER" "6.3" "$1" "$2" "[]" "$3" "false" "$4" >"$RUNNER_LOG" 2>&1
    )
    echo "$?"
}

# run_matrix <setup_command> <command> - echoes the exit status.
run_matrix() {
    drive_runner "$1" "$2" '{}' ""
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

assert_text() {
    local what="$1" expected="$2" actual="$3"
    if [[ "$expected" != "$actual" ]]; then
        echo "  FAIL $what: expected [$expected], got [$actual]"
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

assert_status "non-zero exit code propagates" "3" "$(run_matrix "" "exit 3")"
assert_status "zero exit code passes through" "0" "$(run_matrix "" "true")"
assert_status "a failing setup command fails the job" "4" "$(run_matrix "exit 4" "true")"
assert_status "the command runs in the setup command's directory" "0" \
    "$(run_matrix "cd subpackage" "test \"\$(basename \"\$PWD\")\" = subpackage")"

# Without a cd the command must run in the working directory; otherwise the previous
# assertion would pass even if the setup command's shell were discarded.
assert_status "without a cd the command runs in the working directory" "1" \
    "$(run_matrix "" "test \"\$(basename \"\$PWD\")\" = subpackage")"

# An entry's environment has to reach the command as written: a value from a YAML
# block scalar carries newlines, and one written empty is still a value.
env_json='{"MULTILINE_VALUE":"first\nsecond","EMPTY_VALUE":""}'
assert_status "an entry with a multi-line environment value runs" "0" \
    "$(drive_runner "" "$WORKDIR/report-env.sh" "$env_json" "")"
assert_text "a multi-line environment value arrives whole" "MULTILINE=first/second" \
    "$(grep '^MULTILINE=' "$WORKDIR/env-report.txt")"
assert_text "an empty environment value is still exported" "EMPTY=" \
    "$(grep '^EMPTY=' "$WORKDIR/env-report.txt")"

# The container path passes the same values as docker -e arguments.
rm -f "$WORKDIR/docker-args.txt"
assert_status "a container entry with a multi-line environment value runs" "0" \
    "$(drive_runner "" "true" "$env_json" "" '{"image":"swift:6.3"}')"
docker_args=$(cat "$WORKDIR/docker-args.txt")
assert_contains "a multi-line environment value reaches the container whole" \
    $'MULTILINE_VALUE=first\nsecond' "$docker_args"
assert_contains "an empty environment value reaches the container" \
    $'\nEMPTY_VALUE=\n' "$docker_args"

# Every SDK type has to hand the caller's build command to the SDK script, which
# otherwise builds with its own default and reports success for work nobody asked
# for. The triples are only read by the Android type.
sdk_build_command="swift build --product Widget"
for sdk_type in static-linux wasm embedded-wasm android; do
    rm -f "$WORKDIR/sdk-args.txt"
    sdk_json='{"type":"'"$sdk_type"'","triples":["aarch64-unknown-linux-android24"]}'
    assert_status "$sdk_type SDK build succeeds" "0" \
        "$(drive_runner "" "$sdk_build_command" '{}' "$sdk_json")"
    assert_contains "$sdk_type passes the caller's build command" \
        "--build-command=$sdk_build_command" "$(cat "$WORKDIR/sdk-args.txt")"
done

# An entry with both a container and an SDK has to be refused here, where the
# container path assumes there is no SDK: it returns before the SDK handling, so it
# would run the raw command and report a green SDK build.
assert_status "a container entry with an SDK is refused" "1" \
    "$(drive_runner "" "true" '{}' '{"type":"wasm"}' '{"image":"swift:6.3"}')"
assert_contains "the refusal says what is wrong" "cannot also specify an SDK" \
    "$(cat "$RUNNER_LOG")"

# The Android build in install-and-build-with-sdk.sh loops over the triples it was
# given, so an invocation with none installs the Swift SDK and the NDK, builds nothing
# and exits 0. The runner reaches that invocation for a hand-written matrix entry with
# no "triples" field, because its jq filter yields nothing rather than failing.
#
# The refusal has to come before anything is fetched, so curl here records the attempt
# and fails: an install that got as far as the network is not a refusal.
SDK_SCRIPT="${REPO_ROOT}/.github/workflows/scripts/install-and-build-with-sdk.sh"
SDK_STUB_DIR="$WORKDIR/sdk-stubs"
CURL_CALLED="$WORKDIR/curl-called.txt"
mkdir -p "$SDK_STUB_DIR"
cat >"$SDK_STUB_DIR/curl" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >>"$CURL_CALLED"
exit 1
STUB
chmod +x "$SDK_STUB_DIR/curl"

# refuse_android_build <what> <message needle> <argument>... - asserts the SDK script
# refuses the arguments, says so in terms the caller can act on, and fetches nothing.
#
# The exit status alone proves little here: curl fails, so a script that did not refuse
# would also exit 1, on the download it should never have started.
refuse_android_build() {
    local what="$1" needle="$2"
    shift 2

    local log="$WORKDIR/android-refusal.log"
    rm -f "$CURL_CALLED"
    PATH="$SDK_STUB_DIR:$PATH" "$SDK_SCRIPT" --android --android-ndk-version=r27d \
        "$@" --flags="" --build-command="swift build" "6.3" >"$log" 2>&1
    local status=$?

    assert_status "$what is refused" "1" "$status"
    assert_contains "the refusal for $what names the argument" "$needle" "$(cat "$log")"
    assert_text "nothing is fetched before the refusal for $what" "no" \
        "$(if [[ -e "$CURL_CALLED" ]]; then echo yes; else echo no; fi)"
}

refuse_android_build "an Android build with no triples" \
    "--android-sdk-triple=<triple> must be specified"

# A triple given as the empty string is a one-element list, so it passes the count
# check and reaches the compiler as a --swift-sdk with nothing after it. An adopter
# handing android_sdk_triples: "[]" to swift_package_test.yml writes exactly that,
# because join() over an empty array is the empty string.
refuse_android_build "an Android build with an empty triple" \
    "--android-sdk-triple was given a blank value" \
    "--android-sdk-triple="
refuse_android_build "an Android build with a whitespace-only triple" \
    "--android-sdk-triple was given a blank value" \
    "--android-sdk-triple=   "

# The script runs under 'set -u', and ANDROID_NDK_HOME is set by a GitHub runner rather
# than by the script, so every read of it has to tolerate its being unset. Two log lines
# report the NDK directory: one before the NDK is installed, one before the build.
#
# These stubs take the Android path all the way through to the build without a network
# or a toolchain. 'swift sdk list' decides which of the two log lines is reached: an
# already-installed SDK returns early and reaches only the second.
ANDROID_STUB_DIR="$WORKDIR/android-stubs"
ANDROID_HOME_DIR="$WORKDIR/android-home"
mkdir -p "$ANDROID_STUB_DIR" "$ANDROID_HOME_DIR/.config/swiftpm"

cat >"$ANDROID_STUB_DIR/curl" <<'STUB'
#!/bin/bash
# Serves the releases index and writes an empty file for the NDK archive.
output=""
url=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        http*) url="$1"; shift ;;
        *) shift ;;
    esac
done
case "$url" in
    *releases.json)
        printf '%s' '[{"name":"6.3","platforms":[{"platform":"android-sdk","checksum":"0badc0de"}]}]'
        ;;
    *dl.google.com*) : >"$output" ;;
    *) exit 1 ;;
esac
STUB

cat >"$ANDROID_STUB_DIR/swift" <<'STUB'
#!/bin/bash
case "$1" in
    --version) echo "Swift version 6.3 (swift-6.3-RELEASE)" ;;
    sdk) [[ "$2" == list ]] && printf '%s\n' "$ANDROID_SDK_LIST" ;;
esac
exit 0
STUB

# The NDK archive is never unpacked for real: on the 6.3 path the directory is only
# logged, never read.
printf '#!/bin/bash\nexit 0\n' >"$ANDROID_STUB_DIR/unzip"
chmod +x "$ANDROID_STUB_DIR/curl" "$ANDROID_STUB_DIR/swift" "$ANDROID_STUB_DIR/unzip"

# run_android_build <sdk list output> <log> - echoes the exit status.
run_android_build() {
    (
        cd "$WORKDIR" || exit 1
        # A GitHub runner presets ANDROID_NDK_HOME, so the test says nothing unless it
        # is removed. GITHUB_ENV goes too, so the script does not append to the
        # environment file of the job running these tests.
        unset ANDROID_NDK_HOME GITHUB_ENV
        PATH="$ANDROID_STUB_DIR:$PATH" \
        HOME="$ANDROID_HOME_DIR" \
        ANDROID_SDK_LIST="$1" \
            "$SDK_SCRIPT" --android --android-ndk-version=r27d \
            --android-sdk-triple=aarch64-unknown-linux-android24 \
            --flags="" --build-command="swift build" "6.3" >"$2" 2>&1
    )
    echo "$?"
}

# An installed SDK skips the install and reaches only the log line before the build.
ANDROID_BUILD_LOG="$WORKDIR/android-installed.log"
assert_status "an Android build with ANDROID_NDK_HOME unset runs" "0" \
    "$(run_android_build "swift-6.3-RELEASE_android" "$ANDROID_BUILD_LOG")"
android_build_log=$(cat "$ANDROID_BUILD_LOG")
assert_lacks "the build does not die on an unset ANDROID_NDK_HOME" \
    "unbound variable" "$android_build_log"
assert_contains "the build reports an unset NDK directory as unset" \
    "Using NDK at (unset)" "$android_build_log"
# The same run shows the validation above lets a well-formed triple through.
assert_contains "a valid triple reaches the build command" \
    "Running: swift build --swift-sdk aarch64-unknown-linux-android24" "$android_build_log"

# A tag that does not match the installed-SDK pattern takes the install path, which
# reports the NDK directory before deciding whether to download one.
ANDROID_INSTALL_LOG="$WORKDIR/android-installing.log"
assert_status "an Android SDK install with ANDROID_NDK_HOME unset runs" "0" \
    "$(run_android_build "swift-6.3-RELEASE-android-0.1" "$ANDROID_INSTALL_LOG")"
android_install_log=$(cat "$ANDROID_INSTALL_LOG")
assert_lacks "the install does not die on an unset ANDROID_NDK_HOME" \
    "unbound variable" "$android_install_log"
assert_contains "the install reports an unset NDK directory as unset" \
    "Checking for Android NDK r27d at (unset)" "$android_install_log"
assert_contains "the install then reports the NDK it downloaded" \
    "Using NDK at ${ANDROID_HOME_DIR}/.config/swiftpm/android-ndk-r27d" "$android_install_log"

if [[ "$failures" -gt 0 ]]; then
    printf '\n%d failed\n' "$failures"
    exit 1
fi
printf '\nall passed\n'

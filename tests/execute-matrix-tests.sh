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

# Tests the shell execute_matrix.yml carries, and the parts of its dispatch a script
# cannot reach.
#
# The matrix string is the boundary between the generator and the executor: input that
# names no entries has to be told apart from input that is empty, misspelled or
# unparseable, all of which otherwise fan out to zero jobs and a green check.
#
# The FreeBSD dispatch runs in a VM rather than through a runner script, so it is the
# one path where an entry's command arguments, environment and ${SCRIPTS_ROOT} can go
# missing without a script to notice. Each step's script is taken from the workflow and
# run here, with swift stubbed, so the tests need no VM and no toolchain.
#
# Where cross-pr-checkout.swift clones a linked pull request is tested here too: the
# dispatch is what puts the script in a container, whose mount is the reason the location
# is not simply the checkout's parent directory.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${REPO_ROOT}/.github/workflows/execute_matrix.yml"
LABEL_WORKFLOW="${REPO_ROOT}/.github/workflows/pull_request_label.yml"

failures=0

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

STUB_DIR="$WORKDIR/stubs"
VM_SCRIPTS_DIR="$WORKDIR/github-workflows/.github/workflows/scripts"
mkdir -p "$STUB_DIR" "$VM_SCRIPTS_DIR"

# The FreeBSD script reports the toolchain version before it builds.
printf '#!/bin/bash\nexit 0\n' >"$STUB_DIR/swift"

# Stands in for a matrix entry's command: records its arguments, the environment the
# entry asked for, and where ${SCRIPTS_ROOT} landed.
cat >"$WORKDIR/record.sh" <<'RECORD'
#!/bin/bash
printf '%s\n' "$@" >"$RECORD_ARGUMENTS"
{
    printf 'FROM_ENTRY=%s\n' "${FROM_ENTRY-unset}"
    printf 'SCRIPTS_ROOT=%s\n' "${SCRIPTS_ROOT-unset}"
} >"$RECORD_ENVIRONMENT"
RECORD

chmod +x "$STUB_DIR/swift" "$WORKDIR/record.sh"

step_script() {
    yq "$1" "$WORKFLOW"
}

CONVERT_SCRIPT=$(step_script '.jobs.convert-matrix.steps[] | select(.id == "convert") | .run')
FREEBSD_ENV_SCRIPT=$(step_script '.jobs.execute-matrix.steps[] | select(.id == "freebsd_env") | .run')
FREEBSD_ARGUMENTS_SCRIPT=$(step_script '.jobs.execute-matrix.steps[] | select(.id == "freebsd_arguments") | .run')
FREEBSD_RUN_SCRIPT=$(step_script '.jobs.execute-matrix.steps[] | select(.name == "Run matrix job (FreeBSD)") | .with.run')

STEP_LOG="$WORKDIR/step.log"
STEP_OUTPUT="$WORKDIR/github_output"

# run_convert <matrix_yaml> [default_command] - echoes the exit status; the step's
# output is left in $STEP_OUTPUT and its log in $STEP_LOG.
run_convert() {
    : >"$STEP_OUTPUT"
    (
        cd "$WORKDIR" || exit 1
        GITHUB_OUTPUT="$STEP_OUTPUT" \
        MATRIX_YAML="$1" \
        DEFAULT_COMMAND="${2:-}" \
        DEFAULT_SETUP_COMMAND="" \
        DEFAULT_COMMAND_ARGUMENTS="" \
        DEFAULT_ENV="{}" \
            bash -c "$CONVERT_SCRIPT" >"$STEP_LOG" 2>&1
    )
    echo "$?"
}

# run_freebsd_env <freebsd_env_vars> <matrix_env_json> - echoes the exit status.
run_freebsd_env() {
    : >"$STEP_OUTPUT"
    (
        cd "$WORKDIR" || exit 1
        GITHUB_OUTPUT="$STEP_OUTPUT" \
        FREEBSD_ENV_VARS="$1" \
        MATRIX_ENV="$2" \
            bash -c "$FREEBSD_ENV_SCRIPT" >"$STEP_LOG" 2>&1
    )
    echo "$?"
}

# run_freebsd_arguments <command_arguments_json> - echoes the quoted arguments the host
# hands the VM.
run_freebsd_arguments() {
    : >"$STEP_OUTPUT"
    (
        cd "$WORKDIR" || exit 1
        GITHUB_OUTPUT="$STEP_OUTPUT" \
        MATRIX_COMMAND_ARGUMENTS="$1" \
            bash -c "$FREEBSD_ARGUMENTS_SCRIPT" >"$STEP_LOG" 2>&1
    )
    output_block command_arguments
}

# run_freebsd_vm <freebsd_env_vars> <setup_command> <command_arguments> - echoes the exit
# status. Run under sh, which is what the VM runs it with.
run_freebsd_vm() {
    rm -f "$WORKDIR/arguments.txt" "$WORKDIR/environment.txt"
    (
        cd "$WORKDIR" || exit 1
        PATH="$STUB_DIR:$PATH" \
        RECORD_ARGUMENTS="$WORKDIR/arguments.txt" \
        RECORD_ENVIRONMENT="$WORKDIR/environment.txt" \
        FREEBSD_ENV_VARS="$1" \
        MATRIX_SETUP_COMMAND="$2" \
        MATRIX_COMMAND="$WORKDIR/record.sh" \
        MATRIX_COMMAND_ARGUMENTS="$3" \
        BUILD_FLAGS="--from-build-flags" \
        SCRIPTS_ROOT_RELATIVE="github-workflows/.github/workflows/scripts" \
        CROSS_PR_TESTING="false" \
            sh -c "$FREEBSD_RUN_SCRIPT" >"$STEP_LOG" 2>&1
    )
    echo "$?"
}

# The heredoc form a step writes a multi-line output with.
output_block() {
    sed -n "/^$1<</,/^[A-Z_]*EOF\$/p" "$STEP_OUTPUT" | sed '1d;$d'
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

echo "== Matrix conversion"

assert_status "an empty matrix string is refused" "1" "$(run_convert "")"
assert_contains "the refusal says the string is empty" "matrix_yaml_string is empty" \
    "$(cat "$STEP_LOG")"
assert_status "a whitespace-only matrix string is refused" "1" "$(run_convert $'\n   \n')"

assert_status "unparseable YAML is refused" "1" "$(run_convert 'config: [')"
assert_contains "the refusal says the YAML is invalid" "not valid YAML" "$(cat "$STEP_LOG")"

# A misspelled key is the failure mode that matters: the caller wrote a matrix, and
# every entry in it would be dropped.
assert_status "a matrix with no config key is refused" "1" \
    "$(run_convert $'configs:\n  - platform: Linux\n    name: entry\n    command: "true"\n')"
assert_contains "the refusal names the config key" "no 'config' key" "$(cat "$STEP_LOG")"

assert_status "a config that is not a list is refused" "1" \
    "$(run_convert $'config:\n  platform: Linux\n  name: entry\n')"
assert_contains "the refusal says config must be a list" "must be a list" "$(cat "$STEP_LOG")"

# A caller that disables every platform legitimately produces this.
assert_status "an entryless matrix is accepted" "0" "$(run_convert 'config: []')"
assert_text "an entryless matrix runs no jobs" "job_count=0" "$(grep '^job_count=' "$STEP_OUTPUT")"

valid_matrix=$'config:\n  - platform: Linux\n    name: entry\n    runner: [ubuntu-24.04]\n'
assert_status "a matrix with an entry is accepted" "0" "$(run_convert "$valid_matrix" "swift build")"
assert_text "the entry becomes one job" "job_count=1" "$(grep '^job_count=' "$STEP_OUTPUT")"
assert_contains "the caller's command fills the entry" '"command":"swift build"' \
    "$(output_block matrix)"

# The generator can be asked for JSON, and a caller can hand-write it.
assert_status "a matrix written as JSON is accepted" "0" \
    "$(run_convert '{"config":[{"platform":"Linux","name":"entry","command":"true"}]}')"
assert_text "the JSON entry becomes one job" "job_count=1" "$(grep '^job_count=' "$STEP_OUTPUT")"

# The checks that follow the conversion have to keep seeing the entries.
assert_status "an entry with no command anywhere is refused" "1" "$(run_convert "$valid_matrix")"
assert_contains "the refusal names the entry" "No command for matrix entries: entry" \
    "$(cat "$STEP_LOG")"
assert_status "an entry on an unsupported platform is refused" "1" \
    "$(run_convert $'config:\n  - platform: Solaris\n    name: entry\n    command: "true"\n')"
assert_contains "the refusal names the platform" "Unsupported platform" "$(cat "$STEP_LOG")"

echo "== FreeBSD environment"

assert_status "the environments merge" "0" "$(run_freebsd_env "FROM_FREEBSD=1" '{"FROM_ENTRY":"2"}')"
assert_text "both sources reach the VM" $'FROM_FREEBSD=1\nFROM_ENTRY=2' "$(output_block env_vars)"

# freebsd.env_vars and the entry's env can name the same variable; the VM exports the
# lines in order, so the entry's value has to come last.
assert_status "a variable set by both merges" "0" "$(run_freebsd_env "SHARED=freebsd" '{"SHARED":"entry"}')"
assert_text "the entry's value wins" "SHARED=entry" "$(output_block env_vars | tail -1)"

assert_status "an empty environment merges" "0" "$(run_freebsd_env "" '{}')"
assert_text "an empty environment stays empty" "" "$(output_block env_vars)"

# A value spanning lines cannot be carried as a KEY=VALUE line, and arriving cut short is
# worse than not arriving.
assert_status "a multi-line value is refused" "1" \
    "$(run_freebsd_env "" '{"FROM_ENTRY":"first\nsecond"}')"
assert_contains "the refusal says what is wrong" "spanning several lines" "$(cat "$STEP_LOG")"

echo "== FreeBSD dispatch"

assert_status "the VM script runs the entry's command" "0" \
    "$(run_freebsd_vm "FROM_ENTRY=yes" "" "-Xswiftc -warnings-as-errors")"
assert_contains "the entry's command arguments reach the command" \
    $'-Xswiftc\n-warnings-as-errors' "$(cat "$WORKDIR/arguments.txt")"
assert_contains "freebsd.build_flags still reach the command" "--from-build-flags" \
    "$(cat "$WORKDIR/arguments.txt")"
assert_text "the entry's environment reaches the command" "FROM_ENTRY=yes" \
    "$(grep '^FROM_ENTRY=' "$WORKDIR/environment.txt")"
assert_text "\${SCRIPTS_ROOT} points at the VM's copy of the scripts" \
    "SCRIPTS_ROOT=$VM_SCRIPTS_DIR" "$(grep '^SCRIPTS_ROOT=' "$WORKDIR/environment.txt")"

# A blank line in the environment is not a variable, and exporting it would fail the job
# under set -e.
assert_status "a blank environment line is skipped" "0" \
    "$(run_freebsd_vm $'\nFROM_ENTRY=yes\n' "" "")"

assert_status "a failing setup command fails the job" "7" "$(run_freebsd_vm "" "exit 7" "")"

echo "== FreeBSD command arguments"

# The VM has no jq, so the host quotes the entry's arguments and the VM eval's them. Each
# element of the list is one argument on every other platform, and has to be one here too.
assert_status "an argument containing a space is accepted" "0" \
    "$(run_freebsd_vm "" "" "$(run_freebsd_arguments '["-Xswiftc","-DFOO=bar baz"]')")"
assert_text "an argument containing a space stays one argument" \
    $'--from-build-flags\n-Xswiftc\n-DFOO=bar baz' "$(cat "$WORKDIR/arguments.txt")"

# A single quote is what the quoting itself is written in, so an argument holding one
# would break the eval and fail the job rather than run the wrong tests.
assert_status "an argument containing a single quote is accepted" "0" \
    "$(run_freebsd_vm "" "" "$(run_freebsd_arguments '["--filter=Don'\''t"]')")"
assert_text "an argument containing a single quote arrives whole" \
    $'--from-build-flags\n--filter=Don\'t' "$(cat "$WORKDIR/arguments.txt")"

assert_status "an entry with no arguments is accepted" "0" \
    "$(run_freebsd_vm "" "" "$(run_freebsd_arguments '[]')")"
assert_text "an entry with no arguments adds none" "--from-build-flags" \
    "$(cat "$WORKDIR/arguments.txt")"

# A hand-written entry may give the space-separated string the workflow input takes.
assert_text "a string is passed through" "-a -b" "$(run_freebsd_arguments '"-a -b"')"

echo "== Linked pull request checkouts"

# Where a linked pull request is cloned is a decision cross-pr-checkout.swift makes from
# its working directory, and running the script to reach it needs a pull request to clone,
# so the decision is compiled on its own and exercised with the paths a job presents.
CROSS_PR_SCRIPT="${REPO_ROOT}/.github/workflows/scripts/cross-pr-checkout.swift"
if command -v swift > /dev/null; then
    DRIVER="$WORKDIR/linked-pull-requests.swift"
    {
        echo "import Foundation"
        sed -n '/^func linkedPullRequestsDirectory/,/^}/p' "$CROSS_PR_SCRIPT"
        cat <<'DRIVER'
print(
  linkedPullRequestsDirectory(
    checkout: URL(fileURLWithPath: "/home/runner/work/swift-nio/swift-nio"),
    parent: URL(fileURLWithPath: "/home/runner/work/swift-nio")
  ).path
)
print(
  linkedPullRequestsDirectory(
    checkout: URL(fileURLWithPath: "/swift-nio"),
    parent: URL(fileURLWithPath: "/")
  ).path
)
DRIVER
    } >"$DRIVER"

    if chosen=$(swift "$DRIVER" 2>"$STEP_LOG"); then
        assert_text "a checkout beside its siblings clones into the parent directory" \
            "/home/runner/work/swift-nio" "$(sed -n 1p <<<"$chosen")"
        # A container mounts the checkout at the root of its own filesystem, so a clone in
        # the parent directory is not on the mount: the host never sees it and it does not
        # outlive the container.
        assert_text "a container's checkout clones below itself" \
            "/swift-nio/.linked-pull-requests" "$(sed -n 2p <<<"$chosen")"
    else
        echo "  FAIL the clone location does not compile: $(cat "$STEP_LOG")"
        failures=$((failures + 1))
    fi
else
    echo "  skip the clone location needs swift to compile"
fi

echo "== Workflow declarations"

# job_timeout is documented as the bound on every job, so every step that runs one has
# to carry a timeout: a hung VM or emulator otherwise runs to the six-hour default.
for step in \
    "Run matrix job (Linux)" \
    "Run Android emulator tests" \
    "Run matrix job (Windows)" \
    "Run matrix job (macOS)" \
    "Run matrix job (FreeBSD)"
do
    timeout_expression=$(yq ".jobs.execute-matrix.steps[] | select(.name == \"$step\") | .[\"timeout-minutes\"] // \"none\"" "$WORKFLOW")
    if [[ -n "$timeout_expression" && "$timeout_expression" != "none" ]]; then
        echo "  ok   $step is bounded by a timeout"
    else
        echo "  FAIL $step has no timeout-minutes"
        failures=$((failures + 1))
    fi
done

# The VM receives only what envs: names, so a variable the step defines and does not
# name arrives empty - and a path built from it silently loses its prefix.
freebsd_envs=$(yq '.jobs.execute-matrix.steps[] | select(.name == "Run matrix job (FreeBSD)") | .with.envs' "$WORKFLOW")
while IFS= read -r name; do
    if [[ " $freebsd_envs " == *" $name "* ]]; then
        echo "  ok   $name reaches the FreeBSD VM"
    else
        echo "  FAIL $name is set for the FreeBSD step but not named in envs:"
        failures=$((failures + 1))
    fi
done < <(yq '.jobs.execute-matrix.steps[] | select(.name == "Run matrix job (FreeBSD)") | .env | keys | .[]' "$WORKFLOW")

# gh pr view reads pull-request metadata, which contents: read does not cover.
assert_text "the label check may read pull requests" "read" \
    "$(yq '.permissions["pull-requests"]' "$LABEL_WORKFLOW")"

if [[ "$failures" -gt 0 ]]; then
    printf '\n%d failed\n' "$failures"
    exit 1
fi
printf '\nall passed\n'

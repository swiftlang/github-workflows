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

# Tests how run-check.sh runs the caller's pre-build command and rejects what it cannot run.
#
# The check scripts are stubbed, so the tests need no toolchain: what is under test is the
# dispatch and the shell options the pre-build command runs under.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
run_check="${repo_root}/.github/workflows/scripts/soundness/run-check.sh"

failures=0
scratch=$(mktemp -d)
trap 'rm -rf "${scratch}"' EXIT

# A scripts directory whose docs check only records that it ran.
scripts="${scratch}/scripts"
ran_marker="${scratch}/ran"
mkdir -p "${scripts}"
cat >"${scripts}/check-docs.sh" <<'STUB'
#!/bin/bash
touch "${RAN_MARKER}"
STUB
chmod +x "${scripts}/check-docs.sh"

# Runs the docs check with a pre-build command, from an empty environment so that nothing
# exported in the caller's shell reaches it. Prints the exit status and whether the check ran.
run_docs_check() {
    rm -f "${ran_marker}"
    local status=0
    env -i PATH="${PATH}" HOME="${HOME}" SCRIPTS_DIRECTORY="${scripts}" RAN_MARKER="${ran_marker}" \
        LINUX_PRE_BUILD_COMMAND="$1" "${run_check}" docs >/dev/null 2>&1 || status=$?
    local ran=no
    [[ -e "${ran_marker}" ]] && ran=yes
    echo "exit=${status} ran=${ran}"
}

expect() {
    local description="$1" expected="$2" actual="$3"
    if [[ "${actual}" == "${expected}" ]]; then
        echo "PASS: ${description}"
    else
        echo "FAIL: ${description}"
        echo "  expected: ${expected}"
        echo "  actual:   ${actual}"
        failures=$((failures + 1))
    fi
}

expect "a pre-build command that succeeds lets the check run" "exit=0 ran=yes" \
    "$(run_docs_check 'true')"

expect "a pre-build command that fails stops the check" "exit=1 ran=no" \
    "$(run_docs_check 'false')"

# The caller wrote the command for a shell without `pipefail`, so an early stage that fails
# must not fail the pipeline.
expect "a pipeline in the pre-build command is judged by its last stage" "exit=0 ran=yes" \
    "$(run_docs_check 'false | true')"

unknown_error=$(env -i PATH="${PATH}" SCRIPTS_DIRECTORY="${scripts}" "${run_check}" nonsense 2>&1 >/dev/null || true)
expect "an unknown check is rejected by name" "** ERROR: unknown soundness check 'nonsense'" "${unknown_error}"

if env -i PATH="${PATH}" "${run_check}" docs >/dev/null 2>&1; then
    echo "FAIL: a run without SCRIPTS_DIRECTORY was accepted"
    failures=$((failures + 1))
else
    echo "PASS: a run without SCRIPTS_DIRECTORY is rejected"
fi

if [[ "${failures}" -ne 0 ]]; then
    echo "${failures} failure(s)"
    exit 1
fi

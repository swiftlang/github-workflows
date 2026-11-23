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

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
plan="${repo_root}/.github/workflows/scripts/soundness/plan-checks.sh"

failures=0

# Runs the planner with only the inputs a workflow's defaults would give it, plus the
# overrides in the arguments, and prints its JSON. Starting from an empty environment
# keeps a variable already exported in the caller's shell from satisfying a required input.
plan_json() {
    env -i PATH="${PATH}" \
        API_BREAKAGE_CHECK_ENABLED=true \
        API_BREAKAGE_CHECK_CONTAINER_IMAGE=swift:6.3-noble \
        DOCS_CHECK_ENABLED=true \
        DOCS_CHECK_CONTAINER_IMAGE=swift:6.3-noble \
        DOCS_CHECK_MACOS_ENABLED=false \
        DOCS_CHECK_MACOS_VERSION=tahoe \
        DOCS_CHECK_MACOS_ARCH=ARM64 \
        UNACCEPTABLE_LANGUAGE_CHECK_ENABLED=true \
        LICENSE_HEADER_CHECK_ENABLED=true \
        BROKEN_SYMLINK_CHECK_ENABLED=true \
        FORMAT_CHECK_ENABLED=true \
        FORMAT_CHECK_CONTAINER_IMAGE=swift:6.3-noble \
        SHELL_CHECK_ENABLED=true \
        SHELL_CHECK_CONTAINER_IMAGE=ubuntu:noble \
        YAMLLINT_CHECK_ENABLED=true \
        PYTHON_LINT_CHECK_ENABLED=true \
        "$@" \
        "${plan}"
}

planned_names() {
    plan_json "$@" | jq -r '[.include[].name] | join(",")'
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

everything_default="API breakage check,Documentation check,Unacceptable language check,License headers check,Broken symlinks check,Format check,Shell check,YAML lint check,Python lint check"

expect "defaults plan every check but macOS docs" "${everything_default}" "$(planned_names)"

expect "a disabled check has no entry" \
    "Documentation check,Unacceptable language check,License headers check,Broken symlinks check,Format check,Shell check,YAML lint check,Python lint check" \
    "$(planned_names API_BREAKAGE_CHECK_ENABLED=false)"

expect "macOS docs is planned after Linux docs" \
    "API breakage check,Documentation check,Documentation check (macOS),Unacceptable language check,License headers check,Broken symlinks check,Format check,Shell check,YAML lint check,Python lint check" \
    "$(planned_names DOCS_CHECK_MACOS_ENABLED=true)"

expect "only the docs check remains" "Documentation check" \
    "$(planned_names \
        API_BREAKAGE_CHECK_ENABLED=false UNACCEPTABLE_LANGUAGE_CHECK_ENABLED=false \
        LICENSE_HEADER_CHECK_ENABLED=false BROKEN_SYMLINK_CHECK_ENABLED=false \
        FORMAT_CHECK_ENABLED=false SHELL_CHECK_ENABLED=false \
        YAMLLINT_CHECK_ENABLED=false PYTHON_LINT_CHECK_ENABLED=false)"

macos_plan=$(plan_json DOCS_CHECK_MACOS_ENABLED=true DOCS_CHECK_MACOS_VERSION=sequoia \
    DOCS_CHECK_MACOS_ARCH=X64 DOCS_CHECK_CONTAINER_IMAGE=swift:6.4-noble)

expect "the Linux docs check runs in the image it was given" "swift:6.4-noble" \
    "$(jq -r '.include[] | select(.check == "docs") | .container' <<<"${macos_plan}")"

expect "the macOS docs check runs on the labels it was given, outside a container" \
    '["self-hosted","macos","sequoia","X64"]|' \
    "$(jq -r '.include[] | select(.check == "docs-macos") | "\(.runner | tojson)|\(.container)"' <<<"${macos_plan}")"

expect "only the API breakage check fetches full history" "api-breakage" \
    "$(plan_json | jq -r '[.include[] | select(.full_history) | .check] | join(",")')"

expect "the macOS inputs are not required while the macOS docs check is off" "${everything_default}" \
    "$(planned_names DOCS_CHECK_MACOS_VERSION= DOCS_CHECK_MACOS_ARCH=)"

expect "each check runs in its own container, with its own timeout" \
    "api-breakage=swift:6.3-noble@40,docs=swift:6.3-noble@20,unacceptable-language=@1,license-header=@1,broken-symlink=@1,format=swift:6.3-noble@20,shell=ubuntu:noble@5,yaml-lint=@5,python-lint=@5" \
    "$(plan_json | jq -r '[.include[] | "\(.check)=\(.container)@\(.timeout_minutes)"] | join(",")')"

expect "no check enabled plans no entry" '{"include":[]}' \
    "$(plan_json \
        API_BREAKAGE_CHECK_ENABLED=false DOCS_CHECK_ENABLED=false \
        UNACCEPTABLE_LANGUAGE_CHECK_ENABLED=false LICENSE_HEADER_CHECK_ENABLED=false \
        BROKEN_SYMLINK_CHECK_ENABLED=false FORMAT_CHECK_ENABLED=false SHELL_CHECK_ENABLED=false \
        YAMLLINT_CHECK_ENABLED=false PYTHON_LINT_CHECK_ENABLED=false)"

# A check that is off does not read its container image, so a caller can blank the image of a check it turned off.
expect "a disabled check does not need its container image" \
    "API breakage check,Documentation check,Unacceptable language check,License headers check,Broken symlinks check,Shell check,YAML lint check,Python lint check" \
    "$(planned_names FORMAT_CHECK_ENABLED=false FORMAT_CHECK_CONTAINER_IMAGE=)"

if error=$(planned_names FORMAT_CHECK_CONTAINER_IMAGE= 2>&1 >/dev/null) \
    || [[ "${error}" != *FORMAT_CHECK_CONTAINER_IMAGE* ]]; then
    echo "FAIL: an enabled check with no container image was not rejected by name"
    echo "  error: ${error}"
    failures=$((failures + 1))
else
    echo "PASS: an enabled check with no container image is rejected by name"
fi

if planned_names FORMAT_CHECK_ENABLED=yes >/dev/null 2>&1; then
    echo "FAIL: a value that is not true or false was accepted"
    failures=$((failures + 1))
else
    echo "PASS: a value that is not true or false is rejected"
fi

if [[ "${failures}" -ne 0 ]]; then
    echo "${failures} failure(s)"
    exit 1
fi

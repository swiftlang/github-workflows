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

# Runs one soundness check, from the root of the repository under test.
#
# Arguments:
#   $1: the check identifier, as plan-checks.sh names it
#
# Environment variables:
#   SCRIPTS_DIRECTORY: the directory holding the check scripts
#   CONFIGS_DIRECTORY: the directory holding the default linter configurations
#
# The workflow inputs that the named check reads are also environment variables, and
# each case below names its own.
#
# Not `-u`: LINUX_PRE_BUILD_COMMAND is the caller's own shell, run under `bash -e`,
# and may expand variables it never set.
set -eo pipefail

check="${1:?usage: run-check.sh <check>}"
scripts="${SCRIPTS_DIRECTORY:?}"

# Runs the caller's pre-build command in this shell, so what it exports reaches the check.
# It was written for `bash -e` without `pipefail`, so a pipeline in it must be judged by its
# last stage.
run_pre_build_command() {
    set +o pipefail
    eval "${LINUX_PRE_BUILD_COMMAND:-}"
    set -o pipefail
}

# Arguments: analyze targets additional_arguments
run_docs_check() {
    local analyze="$1" targets="$2" additional_arguments="$3"
    local -a arguments=()
    if [ "${analyze}" != "true" ]; then
        arguments+=(--no-analyze)
    fi
    if [ "${targets}" != "" ]; then
        # Intentional word splitting: the input is a list of targets.
        # shellcheck disable=SC2206
        arguments+=(--doc-targets ${targets})
    fi
    # Intentional word splitting: the input is a list of arguments.
    # shellcheck disable=SC2086
    "${scripts}/check-docs.sh" "${arguments[@]}" --additional-docc-arguments ${additional_arguments}
}

case "${check}" in
    api-breakage)
        # The repository is cloned again by `swift package diagnose-api-breaking-changes`,
        # which is why the checkout keeps its credentials.
        run_pre_build_command
        if [[ -z "${API_BREAKAGE_CHECK_BASELINE:-}" ]]; then
            git fetch "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}" "${GITHUB_BASE_REF:?no baseline: set api_breakage_check_baseline for a trigger that is not a pull request}:pull-base-ref"
            baseline_ref='pull-base-ref'
        else
            baseline_ref="${API_BREAKAGE_CHECK_BASELINE}"
        fi
        echo "Using baseline: ${baseline_ref}"
        breakage_arguments=()
        if [[ -n "${API_BREAKAGE_CHECK_ALLOWLIST_PATH:-}" ]]; then
            breakage_arguments+=(--breakage-allowlist-path "${API_BREAKAGE_CHECK_ALLOWLIST_PATH}")
        fi
        # Intentional word splitting: the input is a list of arguments.
        # shellcheck disable=SC2086
        swift package diagnose-api-breaking-changes "${baseline_ref}" \
            "${breakage_arguments[@]}" ${API_BREAKAGE_CHECK_ADDITIONAL_ARGUMENTS:-}
        ;;
    docs)
        set -x
        run_pre_build_command
        run_docs_check "${DOCS_CHECK_ANALYZE:-}" "${DOCS_CHECK_TARGETS:-}" "${DOCS_CHECK_ADDITIONAL_ARGUMENTS:-}"
        ;;
    docs-macos)
        export DEVELOPER_DIR="/Applications/Xcode_${DOCS_CHECK_MACOS_XCODE_VERSION:?}.app"
        xcrun swift --version
        xcrun clang --version
        set -x
        run_docs_check "${DOCS_CHECK_MACOS_ANALYZE:-}" "${DOCS_CHECK_MACOS_TARGETS:-}" "${DOCS_CHECK_MACOS_ADDITIONAL_ARGUMENTS:-}"
        ;;
    unacceptable-language)
        "${scripts}/check-unacceptable-language.sh"
        ;;
    license-header)
        "${scripts}/check-license-header.sh"
        ;;
    broken-symlink)
        "${scripts}/check-broken-symlinks.sh"
        ;;
    format)
        "${scripts}/check-swift-format.sh"
        ;;
    shell)
        which shellcheck || (apt -q update && apt -yq install shellcheck)
        git ls-files -z '*.sh' | xargs -0 --no-run-if-empty shellcheck
        ;;
    yaml-lint)
        which yamllint || (apt -q update && apt install -yq yamllint)
        cd "${GITHUB_WORKSPACE}"
        if [ ! -f ".yamllint.yml" ]; then
            echo "Using default yamllint config file"
            cat "${CONFIGS_DIRECTORY:?}/yamllint.yml" > .yamllint.yml
        fi
        yamllint --strict --config-file .yamllint.yml .
        ;;
    python-lint)
        pip3 install flake8 flake8-import-order
        cd "${GITHUB_WORKSPACE}"
        if [ ! -f ".flake8" ]; then
            echo "Using default flake8 config file"
            cat "${CONFIGS_DIRECTORY:?}/.flake8" > .flake8
        fi
        flake8
        ;;
    *)
        echo "** ERROR: unknown soundness check '${check}'" >&2
        exit 1
        ;;
esac

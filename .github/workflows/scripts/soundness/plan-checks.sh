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

# Writes the matrix of soundness checks to run on standard output, as JSON for
# `strategy.matrix`. A check the caller turned off has no entry, so no job exists
# for it and the run shows no skipped job.
#
# Each entry carries:
#   check            - the identifier run-check.sh dispatches on
#   name             - the job name, which is also the status check name
#   runner           - the `runs-on` labels
#   container        - the container image, or empty to run on the runner
#   timeout_minutes  - the job's timeout
#   full_history     - whether the checkout needs every commit and tag
#
# Environment variables, each a workflow input. The enable flags are always required. A
# check's container image is required only while that check is on, and so are the macOS
# version and architecture for the macOS docs check:
#   API_BREAKAGE_CHECK_ENABLED, API_BREAKAGE_CHECK_CONTAINER_IMAGE
#   DOCS_CHECK_ENABLED, DOCS_CHECK_CONTAINER_IMAGE
#   DOCS_CHECK_MACOS_ENABLED, DOCS_CHECK_MACOS_VERSION, DOCS_CHECK_MACOS_ARCH
#   UNACCEPTABLE_LANGUAGE_CHECK_ENABLED, LICENSE_HEADER_CHECK_ENABLED
#   BROKEN_SYMLINK_CHECK_ENABLED
#   FORMAT_CHECK_ENABLED, FORMAT_CHECK_CONTAINER_IMAGE
#   SHELL_CHECK_ENABLED, SHELL_CHECK_CONTAINER_IMAGE
#   YAMLLINT_CHECK_ENABLED, PYTHON_LINT_CHECK_ENABLED

command -v jq >/dev/null || { echo "** ERROR: jq not found on PATH" >&2; exit 1; }

entries="[]"

# Arguments: enabled check name runner_json container_variable timeout_minutes [full_history]
#
# `container_variable` names the variable holding the image the check runs in, or is empty
# for a check that runs on the runner. It is read only when the check is on.
add_check() {
    local enabled="$1" check="$2" name="$3" runner="$4" container_variable="$5" timeout_minutes="$6"
    local full_history="${7:-false}"

    case "$enabled" in
        true) ;;
        false) return 0 ;;
        *)
            echo "** ERROR: the enable input for '$check' is '$enabled', not 'true' or 'false'" >&2
            exit 1
            ;;
    esac

    local container=""
    if [[ -n "$container_variable" ]]; then
        container="${!container_variable:-}"
        if [[ -z "$container" ]]; then
            echo "** ERROR: $container_variable is empty, but the '$check' check is on and runs in a container" >&2
            exit 1
        fi
    fi

    entries=$(jq -c \
        --arg check "$check" \
        --arg name "$name" \
        --argjson runner "$runner" \
        --arg container "$container" \
        --argjson timeout_minutes "$timeout_minutes" \
        --argjson full_history "$full_history" \
        '. + [{
            check: $check,
            name: $name,
            runner: $runner,
            container: $container,
            timeout_minutes: $timeout_minutes,
            full_history: $full_history
        }]' <<<"$entries")
}

hosted='["ubuntu-latest"]'
# The macOS inputs only matter when the check is on.
macos_runner='[]'
if [[ "${DOCS_CHECK_MACOS_ENABLED:?}" == "true" ]]; then
    macos_runner=$(jq -cn \
        --arg version "${DOCS_CHECK_MACOS_VERSION:?}" \
        --arg arch "${DOCS_CHECK_MACOS_ARCH:?}" \
        '["self-hosted", "macos", $version, $arch]')
fi

#         enabled                                    check                 name                          runner          container variable                 timeout_minutes full_history
add_check "${API_BREAKAGE_CHECK_ENABLED:?}"          api-breakage          "API breakage check"          "$hosted"       API_BREAKAGE_CHECK_CONTAINER_IMAGE 40              true
add_check "${DOCS_CHECK_ENABLED:?}"                  docs                  "Documentation check"         "$hosted"       DOCS_CHECK_CONTAINER_IMAGE         20
add_check "${DOCS_CHECK_MACOS_ENABLED:?}"            docs-macos            "Documentation check (macOS)" "$macos_runner" ""                                 20
add_check "${UNACCEPTABLE_LANGUAGE_CHECK_ENABLED:?}" unacceptable-language "Unacceptable language check" "$hosted"       ""                                 1
add_check "${LICENSE_HEADER_CHECK_ENABLED:?}"        license-header        "License headers check"       "$hosted"       ""                                 1
add_check "${BROKEN_SYMLINK_CHECK_ENABLED:?}"        broken-symlink        "Broken symlinks check"       "$hosted"       ""                                 1
add_check "${FORMAT_CHECK_ENABLED:?}"                format                "Format check"                "$hosted"       FORMAT_CHECK_CONTAINER_IMAGE       20
add_check "${SHELL_CHECK_ENABLED:?}"                 shell                 "Shell check"                 "$hosted"       SHELL_CHECK_CONTAINER_IMAGE        5
add_check "${YAMLLINT_CHECK_ENABLED:?}"              yaml-lint             "YAML lint check"             "$hosted"       ""                                 5
add_check "${PYTHON_LINT_CHECK_ENABLED:?}"           python-lint           "Python lint check"           "$hosted"       ""                                 5

jq -c '{include: .}' <<<"$entries"

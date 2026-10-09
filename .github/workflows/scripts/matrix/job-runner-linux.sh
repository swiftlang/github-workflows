#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2025 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

set -euo pipefail

# This script runs commands on a Linux host, either natively (via swiftly)
# or inside a Docker container when CONTAINER_JSON is set.
#
# Arguments:
#   $1: Swift version label (e.g. "6.2", "nightly-release")
#   $2: Setup command (can be empty)
#   $3: Main command to run
#   $4: JSON array or string of command arguments
#   $5: JSON string of environment variables (can be empty)
#   $6: needs_token (true/false, optional)
#   $7: SDK JSON configuration (optional)
#
# Environment variables:
#   CONTAINER_JSON    - JSON with optional Docker container config (image, dockerfile, capabilities)
#   SCRIPTS_ROOT      - Path to the github-workflows scripts directory
#   MATRIX_TOOLCHAIN  - The concrete toolchain identifier for the version label
#                       (e.g. "nightly-6.4.x" for "nightly-release"). Defaults to
#                       the label, which is correct for plain release versions.
#   MATRIX_SWIFTLY    - The swiftly selector for the version label (e.g.
#                       "6.4-snapshot"). Defaults to the label.
#   CROSS_PR_TESTING  - "true" to check out PRs linked from this PR's description,
#                       after the toolchain is installed.
#   CROSS_PR_REPO     - The repository the pull request is against.
#   CROSS_PR_NUMBER   - The pull request number.

swift_version="$1"
setup_command="${2:-}"
command="$3"
command_arguments_json="${4:-}"
env_json="${5:-}"
needs_token="${6:-false}"
sdk_json="${7:-}"

# A hand-written matrix may supply only `swift_version`, so both resolved forms fall
# back to it rather than being re-derived here.
matrix_toolchain="${MATRIX_TOOLCHAIN:-$swift_version}"
matrix_swiftly="${MATRIX_SWIFTLY:-$swift_version}"

log() { echo "** $*" >&2; }

command -v jq >/dev/null || { echo "** ERROR: jq not found on PATH" >&2; exit 1; }

container_json="${CONTAINER_JSON:-null}"
container_image=""
container_dockerfile=""
container_capabilities="[]"
container_security_options="[]"

if [[ -n "$container_json" && "$container_json" != "null" && "$container_json" != '{}' ]]; then
    container_image=$(echo "$container_json" | jq -r '.image // empty')
    container_dockerfile=$(echo "$container_json" | jq -r '.dockerfile // empty')
    container_capabilities=$(echo "$container_json" | jq -c '.capabilities // []')
    container_security_options=$(echo "$container_json" | jq -c '.security_options // []')
fi

parse_command_arguments() {
    if [[ -n "$command_arguments_json" && "$command_arguments_json" != "null" && "$command_arguments_json" != '[]' ]]; then
        if [[ "$command_arguments_json" =~ ^\[.*\]$ ]]; then
            # Shell-quote each argument rather than joining on a space. The command is run
            # through eval, so an argument containing whitespace would otherwise arrive as
            # several - which the schema's array type promises it will not.
            echo "$command_arguments_json" | jq -r 'map(@sh) | join(" ")'
        else
            echo "$command_arguments_json"
        fi
    fi
}

command_arguments=$(parse_command_arguments)

# ---------------------------------------------------------------------------
# Docker execution path
# ---------------------------------------------------------------------------
if [[ -n "$container_image" ]]; then
    # SDK handling lives on the native path below, which this branch never reaches,
    # so an entry carrying both would run the raw command and report a green SDK
    # build for work that was never done.
    if [[ -n "$sdk_json" && "$sdk_json" != "null" && "$sdk_json" != '{}' ]]; then
        log "ERROR: an entry with a container cannot also specify an SDK"
        exit 1
    fi

    log "Running in Docker container: $container_image"

    actual_image="$container_image"

    if [[ -n "$container_dockerfile" ]]; then
        local_tag="local-ci-image:$(echo "$swift_version" | tr ':/' '-')"
        docker buildx build \
            --build-arg SWIFT_IMAGE="$container_image" \
            -f "$container_dockerfile" \
            -t "$local_tag" \
            .
        actual_image="$local_tag"
    else
        docker pull "$actual_image"
    fi

    workspace="/$(basename "${GITHUB_WORKSPACE:-.}")"

    docker_args=(
        "run"
        "-v" "${GITHUB_WORKSPACE:-.}:$workspace"
        "-w" "$workspace"
        "-e" "CI=${CI:-}"
        "-e" "GITHUB_ACTIONS=${GITHUB_ACTIONS:-}"
        "-e" "SWIFT_VERSION=$swift_version"
        "-e" "workspace=$workspace"
    )

    # The scripts directory lives under GITHUB_WORKSPACE, so it is already
    # inside the mount - but at a different absolute path. Translate it so
    # commands that reference ${SCRIPTS_ROOT} resolve inside the container.
    if [[ -n "${SCRIPTS_ROOT:-}" && -n "${GITHUB_WORKSPACE:-}" ]]; then
        docker_args+=("-e" "SCRIPTS_ROOT=${SCRIPTS_ROOT/#$GITHUB_WORKSPACE/$workspace}")
    fi

    if [[ "$container_capabilities" != '[]' ]]; then
        while IFS= read -r cap; do
            docker_args+=("--cap-add=$cap")
        done < <(echo "$container_capabilities" | jq -r '.[]')
    fi

    if [[ "$container_security_options" != '[]' ]]; then
        while IFS= read -r opt; do
            docker_args+=("--security-opt=$opt")
        done < <(echo "$container_security_options" | jq -r '.[]')
    fi

    # Shell-quoted by jq and eval'd rather than read a line at a time, so a value
    # containing a newline arrives whole and an empty one is still passed.
    if [[ -n "$env_json" && "$env_json" != '{}' && "$env_json" != 'null' ]]; then
        env_docker_args=$(echo "$env_json" | jq -r 'to_entries[] | "-e \((.key + "=" + (.value | tostring)) | @sh)"')
        eval "docker_args+=($env_docker_args)"
    fi

    if [[ "$needs_token" == "true" && -n "${GITHUB_TOKEN:-}" ]]; then
        docker_args+=("-e" "GITHUB_TOKEN=$GITHUB_TOKEN")
    fi

    if [[ "${CROSS_PR_TESTING:-false}" == "true" && -n "${CROSS_PR_REPO:-}" ]]; then
        docker_args+=("-e" "CROSS_PR_REPO=$CROSS_PR_REPO")
        docker_args+=("-e" "CROSS_PR_NUMBER=${CROSS_PR_NUMBER:-}")
    fi

    docker_args+=("$actual_image")

    # Check out linked PRs inside the container, where the toolchain under test is.
    # A failure must fail the job.
    inner_command=""
    if [[ "${CROSS_PR_TESTING:-false}" == "true" && -n "${CROSS_PR_REPO:-}" ]]; then
        # Single-quoted deliberately: these must expand inside the container, from
        # the values passed with -e, not on the host where the paths differ.
        # shellcheck disable=SC2016
        inner_command+='cp "${SCRIPTS_ROOT}/cross-pr-checkout.swift" /tmp/cross-pr-checkout.swift'$'\n'
        # shellcheck disable=SC2016
        inner_command+='swift /tmp/cross-pr-checkout.swift "$CROSS_PR_REPO" "$CROSS_PR_NUMBER"'$'\n'
    fi
    if [[ -n "$setup_command" ]]; then
        inner_command+="$setup_command"$'\n'
    fi
    inner_command+="$command $command_arguments"

    docker_args+=("bash" "-ec" "$inner_command")

    log "Executing: docker ${docker_args[*]}"
    docker "${docker_args[@]}"
    exit $?
fi

# ---------------------------------------------------------------------------
# Native execution path (swiftly)
# ---------------------------------------------------------------------------

refresh_package_cache() {
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -y -q
    elif command -v dnf &> /dev/null; then
        sudo dnf makecache -q
    elif command -v yum &> /dev/null; then
        sudo yum makecache -q
    fi
}

install_swiftly() {
    if command -v swiftly &> /dev/null; then
        log "swiftly is already installed"
        return 0
    fi

    log "Installing swiftly..."
    curl -fsSL -O "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
    tar zxf "swiftly-$(uname -m).tar.gz"
    ./swiftly init --quiet-shell-followup --skip-install --assume-yes
    # shellcheck source=/dev/null
    source "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
    hash -r
    rm -f "swiftly-$(uname -m).tar.gz"
    rm -f swiftly
    log "swiftly installed successfully"
}

install_swift() {
    local swiftly_version="$1"

    log "Installing Swift $swiftly_version using swiftly..."
    local post_install_file="/tmp/swiftly-post-install.sh"
    swiftly install "$swiftly_version" --use --post-install-file="$post_install_file"
    if [[ -f "$post_install_file" && -s "$post_install_file" ]]; then
        log "Running post-install commands..."
        cat "$post_install_file"
        sudo bash "$post_install_file"
        rm -f "$post_install_file"
    fi
    log "Swift installed successfully"
    swift --version
}

skip_swift_install="${SKIP_SWIFT_INSTALL:-false}"
if [[ -n "$sdk_json" && "$sdk_json" != "null" && "$sdk_json" != '{}' ]]; then
    skip_swift_install="true"
fi

# Refresh the package cache so swiftly's post-install apt-get does not hit stale mirrors
refresh_package_cache

if [[ "$skip_swift_install" != "true" ]]; then
    install_swiftly
    # shellcheck source=/dev/null
    source "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
    hash -r
    install_swift "$matrix_swiftly"
else
    log "Skipping Swift installation"
    install_swiftly
    # shellcheck source=/dev/null
    source "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
    hash -r
fi

# Check out linked PRs after the toolchain install, so the script is compiled
# with the toolchain under test. Compiling it earlier picks up whatever Swift the
# runner image ships, which is not the one being tested.
if [[ "${CROSS_PR_TESTING:-false}" == "true" && -n "${CROSS_PR_REPO:-}" ]]; then
    cross_pr_script="${SCRIPTS_ROOT:-./.github/workflows/scripts}/cross-pr-checkout.swift"
    log "Checking out linked PRs"
    cp "$cross_pr_script" /tmp/cross-pr-checkout.swift
    swift /tmp/cross-pr-checkout.swift "$CROSS_PR_REPO" "${CROSS_PR_NUMBER:-}"
fi

# Shell-quoted by jq and eval'd rather than read a line at a time, so a value
# containing a newline arrives whole and an empty one is still exported.
if [[ -n "$env_json" && "$env_json" != '{}' && "$env_json" != 'null' ]]; then
    env_exports=$(echo "$env_json" | jq -r 'to_entries[] | "export \(.key)=\((.value | tostring) | @sh)"')
    eval "$env_exports"
fi

# The SDK script matches a toolchain, installs the SDK and builds in one
# invocation, so the toolchain and SDK come from the same snapshot.
if [[ -n "$sdk_json" && "$sdk_json" != "null" && "$sdk_json" != '{}' ]]; then
    sdk_type=$(echo "$sdk_json" | jq -r '.type // empty')

    if [[ -n "$sdk_type" ]]; then
        log "Will build with SDK: $sdk_type"

        sdk_script="${SCRIPTS_ROOT:-./.github/workflows/scripts}/install-and-build-with-sdk.sh"

        sdk_flags="$command_arguments"
        sdk_build_cmd="$command"

        # The SDK script builds in the working directory, so the setup command
        # has to run first - it is how a caller enters a package below the
        # repository root.
        if [[ -n "$setup_command" ]]; then
            log "Running setup command"
            eval "$setup_command"
        fi

        case "$sdk_type" in
            static-linux)
                "$sdk_script" --static --flags="$sdk_flags" --build-command="$sdk_build_cmd" "$matrix_toolchain"
                ;;
            wasm)
                "$sdk_script" --wasm --flags="$sdk_flags" --build-command="$sdk_build_cmd" "$matrix_toolchain"
                ;;
            embedded-wasm)
                "$sdk_script" --embedded-wasm --flags="$sdk_flags" --build-command="$sdk_build_cmd" "$matrix_toolchain"
                ;;
            android)
                ndk_version=$(echo "$sdk_json" | jq -r '.ndk_version // "r27d"')
                triples=$(echo "$sdk_json" | jq -r '.triples[]?' | sed 's/^/--android-sdk-triple=/' | tr '\n' ' ')
                eval "$sdk_script --android --android-ndk-version=$ndk_version $triples --flags=\"$sdk_flags\" --build-command=\"$sdk_build_cmd\" \"\$matrix_toolchain\""
                ;;
            *)
                log "Error: Unknown SDK type: $sdk_type"
                exit 1
                ;;
        esac
        exit $?
    fi
fi

if [[ -n "$setup_command" ]]; then
    log "Running setup command"
    eval "$setup_command"
fi

full_command="$command $command_arguments"
log "Executing command: $full_command"
eval "$full_command"

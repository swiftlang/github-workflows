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

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

# Parse command line options
INSTALL_STATIC_LINUX=false
INSTALL_WASM=false
BUILD_EMBEDDED_WASM=false
SWIFT_VERSION_INPUT=""
SWIFT_BUILD_FLAGS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --static)
            INSTALL_STATIC_LINUX=true
            shift
            ;;
        --wasm)
            INSTALL_WASM=true
            shift
            ;;
        --embedded-wasm)
            INSTALL_WASM=true
            BUILD_EMBEDDED_WASM=true
            shift
            ;;
        --flags=*)
            SWIFT_BUILD_FLAGS="${1#*=}"
            shift
            ;;
        -*)
            fatal "Unknown option: $1"
            ;;
        *)
            if [[ -z "$SWIFT_VERSION_INPUT" ]]; then
                SWIFT_VERSION_INPUT="$1"
            else
                fatal "Multiple Swift versions specified: $SWIFT_VERSION_INPUT and $1"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$SWIFT_VERSION_INPUT" ]]; then
    fatal "Usage: $0 [--static] [--wasm] [--flags=\"<build-flags>\"] <swift-version>"
fi

if [[ "$INSTALL_STATIC_LINUX" == false && "$INSTALL_WASM" == false ]]; then
    fatal "At least one of --static or --wasm must be specified"
fi

log "Requested Swift version: $SWIFT_VERSION_INPUT"
log "Install Static Linux Swift SDK: $INSTALL_STATIC_LINUX"
log "Install Wasm Swift SDK: $INSTALL_WASM"
if [[ -n "$SWIFT_BUILD_FLAGS" ]]; then
    log "Additional build flags: $SWIFT_BUILD_FLAGS"
fi

# Install dependencies
command -v curl >/dev/null || (apt update -q && apt install -yq curl)
command -v jq >/dev/null || (apt update -q && apt install -yq jq)

SWIFT_API_INSTALL_ROOT="https://www.swift.org/api/v1/install"

# Transforms a minor Swift release version into its latest patch version
# and gets the checksum for the patch version's Static Linux and/or Wasm Swift SDK.
#
# $1 (string): A minor Swift version, e.g. "6.1"
# Output: A string of the form "<patch-version>|<static-checksum>|<wasm-checksum>
find_latest_swift_version() {
    local minor_version="$1"

    log "Finding latest patch version for Swift ${minor_version}"
    log "Fetching releases from swift.org API..."

    local releases_json
    releases_json=$(curl -fsSL "${SWIFT_API_INSTALL_ROOT}/releases.json") || fatal "Failed to fetch Swift releases"

    # Find all releases that start with the minor version (e.g, "6.1")
    # Sort them and get the latest one
    local latest_version
    latest_version=$(echo "$releases_json" | jq -r --arg minor "$minor_version" '
        .[]
        | select(.name | startswith($minor))
        | .name
    ' | sort -V | tail -n1)

    if [[ -z "$latest_version" ]]; then
        fatal "No Swift release found for version $minor_version"
    fi

    log "Found latest patch version: $latest_version"

    local static_checksum=""
    if [[ "$INSTALL_STATIC_LINUX" == true ]]; then
        static_checksum=$(echo "$releases_json" | jq -r --arg version "$latest_version" '
            .[]
            | select(.name == $version)
            | .platforms[]
            | select(.platform == "static-sdk")
            | .checksum
        ')

        if [[ -z "$static_linux_checksum" ]]; then
            fatal "No Static Linux Swift SDK checksum found for Swift $latest_version"
        fi

        log "Found Static Linux Swift SDK checksum: ${STATIC_LINUX_SDK_CHECKSUM:0:12}..."
    fi

    local wasm_checksum=""
    if [[ "$INSTALL_WASM" == true ]]; then
        wasm_checksum=$(echo "$releases_json" | jq -r --arg version "$latest_version" '
            .[]
            | select(.name == $version)
            | .platforms[]
            | select(.platform == "wasm-sdk")
            | .checksum
        ')

        if [[ -z "$wasm_checksum" ]]; then
            fatal "No Swift SDK for Wasm checksum found for Swift $latest_version"
        fi

        log "Found Swift SDK for Wasm checksum: ${wasm_checksum:0:12}..."
    fi

    echo "${latest_version}|${static_checksum}|${wasm_checksum}"
}

# Finds the latest Static Linux or Wasm Swift SDK development snapshot
# for the inputted Swift version and its checksum.
#
# $1 (string): Nightly Swift version, e.g. "6.2" or "main"
# $2 (string): "static" or "wasm"
# Output: A string of the form "<snapshot>|<sdk-checksum>",
# e.g. "swift-6.2-DEVELOPMENT-SNAPSHOT-2025-07-29-a|<sdk-checksum>"
find_latest_sdk_snapshot() {
    local version="$1"
    local sdk_name="$2"

    log "Finding latest ${sdk_name}-sdk for Swift nightly-${version}"
    log "Fetching development snapshots from swift.org API..."

    local sdk_json
    sdk_json=$(curl -fsSL "${SWIFT_API_INSTALL_ROOT}/dev/${version}/${sdk_name}-sdk.json") || fatal "Failed to fetch ${sdk_name}-sdk development snapshots"

    # Extract the snapshot tag from the "dir" field of the first (newest) element
    local snapshot_tag
    snapshot_tag=$(echo "$sdk_json" | jq -r '.[0].dir')

    if [[ -z "$snapshot_tag" || "$snapshot_tag" == "null" ]]; then
        fatal "No ${version} snapshot tag found for ${sdk_name}-sdk"
    fi

    log "Found latest ${version} ${sdk_name}-sdk snapshot: $snapshot_tag"

    # Extract the checksum
    local checksum
    checksum=$(echo "$sdk_json" | jq -r '.[0].checksum')

    if [[ -z "$checksum" || "$checksum" == "null" ]]; then
        fatal "No checksum found for ${sdk_name}-sdk snapshot"
    fi

    log "Found ${sdk_name}-sdk checksum: ${checksum:0:12}..."

    echo "${snapshot_tag}|${checksum}"
}

SWIFT_VERSION_BRANCH=""
STATIC_LINUX_SDK_TAG=""
STATIC_LINUX_SDK_CHECKSUM=""
WASM_SDK_TAG=""
WASM_SDK_CHECKSUM=""

# Parse Swift version input which may contain "nightly-"
if [[ "$SWIFT_VERSION_INPUT" == nightly-* ]]; then
    version="${SWIFT_VERSION_INPUT#nightly-}"
    if [[ "$version" == "main" ]]; then
        SWIFT_VERSION_BRANCH="development"
    else
        SWIFT_VERSION_BRANCH="swift-${version}-branch"
    fi

    if [[ "$INSTALL_STATIC_LINUX" == true ]]; then
        static_linux_sdk_info=$(find_latest_sdk_snapshot "$version" "static")

        STATIC_LINUX_SDK_TAG=$(echo "$static_linu_sdk_info" | cut -d'|' -f1)
        STATIC_LINUX_SDK_CHECKSUM=$(echo "$static_linux_sdk_info" | cut -d'|' -f2)
    fi

    if [[ "$INSTALL_WASM" == true ]]; then
        wasm_sdk_info=$(find_latest_sdk_snapshot "$version" "wasm")

        WASM_SDK_TAG=$(echo "$wasm_sdk_info" | cut -d'|' -f1)
        WASM_SDK_CHECKSUM=$(echo "$wasm_sdk_info" | cut -d'|' -f2)
    fi
else
    latest_version_info=$(find_latest_swift_version "$SWIFT_VERSION_INPUT")

    latest_version=$(echo "$latest_version_info" | cut -d'|' -f1)
    SWIFT_VERSION_BRANCH="swift-${latest_version}-release"

    STATIC_LINUX_SDK_TAG="swift-${latest_version}-RELEASE"
    STATIC_LINUX_SDK_CHECKSUM=$(echo "$latest_version_info" | cut -d'|' -f2)

    WASM_SDK_TAG="swift-${latest_version}-RELEASE"
    WASM_SDK_CHECKSUM=$(echo "$latest_version_info" | cut -d'|' -f3)
fi

# Validate that required Swift SDK tags are set
if [[ "$INSTALL_STATIC_LINUX" == true && -z "$STATIC_LINUX_SDK_TAG" ]]; then
    fatal "STATIC_LINUX_SDK_TAG is not set but Static Linux Swift SDK installation was requested"
fi

if [[ "$INSTALL_WASM" == true && -z "$WASM_SDK_TAG" ]]; then
    fatal "WASM_SDK_TAG is not set but Wasm Swift SDK installation was requested"
fi

get_installed_swift_tag() {
    if ! command -v swift >/dev/null 2>&1; then
        log "Swift is not currently installed"
        echo "none"
        return 0
    fi

    # Check for /.swift_tag file
    if [[ -f "/.swift_tag" ]]; then
        local swift_tag
        swift_tag=$(tr -d '\n' < /.swift_tag | tr -d ' ')
        if [[ -n "$swift_tag" ]]; then
            log "✅ Found Swift snapshot tag in /.swift_tag: $swift_tag"
            echo "$swift_tag"
            return 0
        fi
    fi

    # Try to get release version from swift command if available
    local swift_tag
    swift_tag=$(swift --version 2>/dev/null | grep -o "(swift-.*-RELEASE)" | tr -d "()" | head -n1)
    if [[ -n "$swift_tag" ]]; then
        log "✅ Found Swift release tag via `swift --version`: $swift_tag"
        echo "$swift_tag"
        return 0
    fi

    log "Could not find tag of the installed Swift version"
    echo "none"
}

OS_NAME=""
OS_NAME_NO_DOT=""
OS_ARCH_SUFFIX=""

# Detects OS from /etc/os-release and sets global variables
#
# OS_NAME: Lowercased OS name with the version dot included, e.g. ubuntu22.04
# OS_NAME_NO_DOT: Version dot excluded, e.g. ubuntu2204
# OS_ARCH_SUFFIX: "-aarch64" for aarch64 platforms, otherwise ""
initialize_os_info() {
    if [[ -n "$OS_NAME" ]]; then
        log "Already detected OS: $OS_NAME"
        return 0
    fi

    if [[ ! -f /etc/os-release ]]; then
        fatal "Cannot detect OS: /etc/os-release not found"
    fi

    local os_id
    os_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
    local version_id
    version_id=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')

    if [[ -z "$os_id" || -z "$version_id" ]]; then
        fatal "Could not parse OS information from /etc/os-release"
    fi

    log "✅ Detected OS from /etc/os-release: ${os_id}${version_id}"
    OS_NAME="${os_id}${version_id}"
    OS_NAME_NO_DOT="${os_id}$(echo "$version_id" | tr -d '.')"

    local arch
    arch=$(uname -m)
    if [[ "$arch" == "aarch64" ]]; then
        OS_ARCH_SUFFIX="-aarch64"
        log "Detected aarch64 architecture, using suffix: $OS_ARCH_SUFFIX"
    else
        OS_ARCH_SUFFIX=""
        log "Detected $arch architecture, using no suffix"
    fi
}

# Directory for extracted toolchains (if needed to match the SDKs)
TOOLCHAIN_DIR="${HOME}/.swift-toolchains"
SWIFT_DOWNLOAD_ROOT="https://download.swift.org"

download_and_verify() {
    local url="$1"
    local sig_url="$2"
    local output_file="$3"
    local temp_sig="${output_file}.sig"

    log "Downloading ${url}"
    curl -fsSL "$url" -o "$output_file"

    log "Downloading signature"
    curl -fsSL "$sig_url" -o "$temp_sig"

    log "Setting up GPG for verification"
    local gnupghome
    gnupghome="$(mktemp -d)"
    export GNUPGHOME="$gnupghome"
    curl -fSsL https://swift.org/keys/all-keys.asc | zcat -f | gpg --import - >/dev/null 2>&1

    log "Verifying signature"
    if gpg --batch --verify "$temp_sig" "$output_file" >/dev/null 2>&1; then
        log "✅ Signature verification successful"
    else
        fatal "Signature verification failed"
    fi

    rm -rf "$GNUPGHOME" "$temp_sig"
}

# Downloads and extracts the Swift toolchain for the given snapshot tag
#
# $1 (string): A snapshot tag, e.g. "swift-6.2-DEVELOPMENT-SNAPSHOT-2025-07-29-a"
# Output: Path to the installed swift executable
download_and_extract_toolchain() {
    local snapshot_tag="$1"

    log "Downloading Swift toolchain: $snapshot_tag"

    # "https://download.swift.org/swift-6.2-branch/ubuntu2204/swift-6.2-DEVELOPMENT-SNAPSHOT-2025-07-29-a"
    local snapshot_root="${SWIFT_DOWNLOAD_ROOT}/${SWIFT_VERSION_BRANCH}/${OS_NAME_NO_DOT}${OS_ARCH_SUFFIX}/${snapshot_tag}"

    # "swift-6.2-DEVELOPMENT-SNAPSHOT-2025-07-29-a-ubuntu22.04.tar.gz"
    # "swift-6.2-DEVELOPMENT-SNAPSHOT-2025-07-29-a-ubuntu22.04.tar.gz.sig"
    local toolchain_filename="${snapshot_tag}-${OS_NAME}${OS_ARCH_SUFFIX}.tar.gz"
    local toolchain_sig_filename="${toolchain_filename}.sig"

    local toolchain_url="${snapshot_root}/${toolchain_filename}"
    local toolchain_sig_url="${snapshot_root}/${toolchain_sig_filename}"

    # Check if toolchain is available
    local http_code
    http_code=$(curl -sSL --head -w "%{http_code}" -o /dev/null "$toolchain_url")
    if [[ "$http_code" == "404" ]]; then
        log "Toolchain not found: ${toolchain_filename}"
        log "Exiting workflow..."
        # Don't fail the workflow if we can't find the right toolchain
        exit 0
    fi

    # Create toolchain directory
    mkdir -p "$TOOLCHAIN_DIR"
    local toolchain_path="${TOOLCHAIN_DIR}/${snapshot_tag}"

    # Check if toolchain already exists
    if [[ -d "$toolchain_path" && -f "${toolchain_path}/usr/bin/swift" ]]; then
        log "✅ Toolchain already exists at: $toolchain_path"
        echo "$toolchain_path/usr/bin/swift"
        return 0
    fi

    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    local toolchain_file="${temp_dir}/swift_toolchain.tar.gz"

    # Download and verify toolchain
    download_and_verify "$toolchain_url" "$toolchain_sig_url" "$toolchain_file"

    log "Extracting toolchain to: $toolchain_path"
    mkdir -p "$toolchain_path"
    tar -xzf "$toolchain_file" --directory "$toolchain_path" --strip-components=1

    # Clean up
    rm -rf "$temp_dir"

    local swift_executable="${toolchain_path}/usr/bin/swift"
    if [[ -f "$swift_executable" ]]; then
        log "✅ Swift toolchain extracted successfully"
        echo "$swift_executable"
    else
        fatal "Swift executable not found at expected path: $swift_executable"
    fi
}

INSTALLED_SWIFT_TAG=$(get_installed_swift_tag)
SWIFT_EXECUTABLE_FOR_STATIC_LINUX_SDK=""
SWIFT_EXECUTABLE_FOR_WASM_SDK=""

if [[ "$INSTALL_STATIC_LINUX" == true ]]; then
    if [[ "$INSTALLED_SWIFT_TAG" == "$STATIC_LINUX_SDK_TAG" ]]; then
        log "Current toolchain matches Static Linux Swift SDK snapshot: $STATIC_LINUX_SDK_TAG"
        SWIFT_EXECUTABLE_FOR_STATIC_LINUX_SDK="swift"
    else
        log "Installing Swift toolchain to match Static Linux Swift SDK snapshot: $STATIC_LINUX_SDK_TAG"
        initialize_os_info
        SWIFT_EXECUTABLE_FOR_STATIC_LINUX_SDK=$(download_and_extract_toolchain "$STATIC_LINUX_SDK_TAG")
    fi
fi

if [[ "$INSTALL_WASM" == true ]]; then
    if [[ "$INSTALLED_SWIFT_TAG" == "$WASM_SDK_TAG" ]]; then
        log "Current toolchain matches Wasm Swift SDK snapshot: $WASM_SDK_TAG"
        SWIFT_EXECUTABLE_FOR_WASM_SDK="swift"
    else
        log "Installing Swift toolchain to match Wasm Swift SDK snapshot: $WASM_SDK_TAG"
        initialize_os_info
        SWIFT_EXECUTABLE_FOR_WASM_SDK=$(download_and_extract_toolchain "$WASM_SDK_TAG")
    fi
fi

STATIC_LINUX_SDK_DOWNLOAD_ROOT="${SWIFT_DOWNLOAD_ROOT}/${SWIFT_VERSION_BRANCH}/static-sdk"
WASM_SDK_DOWNLOAD_ROOT="${SWIFT_DOWNLOAD_ROOT}/${SWIFT_VERSION_BRANCH}/wasm-sdk"

install_static_linux_sdk() {
    # Check if the static SDK is already installed
    if "$SWIFT_EXECUTABLE_FOR_STATIC_LINUX_SDK" sdk list 2>/dev/null | grep -q "^${STATIC_LINUX_SDK_TAG}_static-linux-0.0.1"; then
        log "✅ Static SDK ${STATIC_LINUX_SDK_TAG} is already installed, skipping installation"
        return 0
    fi

    log "Installing Swift Static SDK: $STATIC_LINUX_SDK_TAG"

    local static_linux_sdk_filename="${STATIC_LINUX_SDK_TAG}_static-linux-0.0.1.artifactbundle.tar.gz"
    local sdk_url="${STATIC_LINUX_SDK_DOWNLOAD_ROOT}/${STATIC_LINUX_SDK_TAG}/${static_linux_sdk_filename}"

    log "Running: ${SWIFT_EXECUTABLE_FOR_STATIC_LINUX_SDK} sdk install ${sdk_url} --checksum ${STATIC_LINUX_SDK_CHECKSUM}"

    if "$SWIFT_EXECUTABLE_FOR_STATIC_LINUX_SDK" sdk install "$sdk_url" --checksum "$STATIC_LINUX_SDK_CHECKSUM"; then
        log "✅ Static SDK installed successfully"
    else
        fatal "Failed to install static SDK"
    fi
}

install_wasm_sdk() {
    # Check if the Wasm SDK is already installed
    if "$SWIFT_EXECUTABLE_FOR_WASM_SDK" sdk list 2>/dev/null | grep -q "^${WASM_SDK_TAG}_wasm"; then
        log "✅ Wasm SDK ${WASM_SDK_TAG} is already installed, skipping installation"
        return 0
    fi

    log "Installing Swift Wasm SDK: $WASM_SDK_TAG"

    local wasm_sdk_filename="${WASM_SDK_TAG}_wasm.artifactbundle.tar.gz"
    local sdk_url="${WASM_SDK_DOWNLOAD_ROOT}/${WASM_SDK_TAG}/${wasm_sdk_filename}"

    log "Running: ${SWIFT_EXECUTABLE_FOR_WASM_SDK} sdk install ${sdk_url} --checksum ${WASM_SDK_CHECKSUM}"

    if "$SWIFT_EXECUTABLE_FOR_WASM_SDK" sdk install "$sdk_url" --checksum "$WASM_SDK_CHECKSUM"; then
        log "✅ Wasm SDK installed successfully"
    else
        fatal "Failed to install Wasm SDK"
    fi
}

install_sdks() {
    if [[ "$INSTALL_STATIC_LINUX" == true ]]; then
        log "Starting install of Swift ${SWIFT_VERSION_INPUT} Static Linux Swift SDK"
        install_static_linux_sdk
    fi

    if [[ "$INSTALL_WASM" == true ]]; then
        log "Starting install of Swift ${SWIFT_VERSION_INPUT} Wasm Swift SDK"
        install_wasm_sdk
    fi
}

build() {
    if [[ "$INSTALL_STATIC_LINUX" == true ]]; then
        log "Running Swift build with static SDK"

        local sdk_name="${STATIC_LINUX_SDK_TAG}_static-linux-0.0.1"
        local build_command="$SWIFT_EXECUTABLE_FOR_STATIC_LINUX_SDK build --swift-sdk $sdk_name"
        if [[ -n "$SWIFT_BUILD_FLAGS" ]]; then
            build_command="$build_command $SWIFT_BUILD_FLAGS"
        fi

        log "Running: $build_command"

        if eval "$build_command"; then
            log "✅ Swift build with static SDK completed successfully"
        else
            fatal "Swift build with static SDK failed"
        fi
    fi

    if [[ "$INSTALL_WASM" == true ]]; then
        log "Running Swift build with Wasm SDK"

        if [[ "$BUILD_EMBEDDED_WASM" == true ]]; then
            local sdk_name="${WASM_SDK_TAG}_wasm-embedded"
        else
            local sdk_name="${WASM_SDK_TAG}_wasm"
        fi

        local build_command="$SWIFT_EXECUTABLE_FOR_WASM_SDK build --swift-sdk $sdk_name"
        if [[ -n "$SWIFT_BUILD_FLAGS" ]]; then
            build_command="$build_command $SWIFT_BUILD_FLAGS"
        fi

        log "Running: $build_command"

        if eval "$build_command"; then
            log "✅ Swift build with Swift SDK for Wasm completed successfully"
        else
            fatal "Swift build with Swift SDK for Wasm failed"
        fi
    fi
}

main() {
    install_sdks
    build
}

main "$@"

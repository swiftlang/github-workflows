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

VERSION="${CMAKE_VERSION:?CMAKE_VERSION is required}"
EXPECTED_SHA="${CMAKE_SHA256:?CMAKE_SHA256 is required}"
OS="${RUNNER_OS:?RUNNER_OS is required}"
ARCH="${RUNNER_ARCH:?RUNNER_ARCH is required}"
TEMP_DIR="${RUNNER_TEMP:?RUNNER_TEMP is required}"

# Normalize hash to lowercase and strip whitespace
EXPECTED_SHA=$(echo "${EXPECTED_SHA}" | tr '[:upper:]' '[:lower:]' | xargs)

# 1. Determine destination directory (fallback to $RUNNER_TEMP/cmake-<version> if unset/empty)
DEST_DIR="${CMAKE_INSTALL_DIR:-}"
if [ -z "${DEST_DIR}" ]; then
  DEST_DIR="${TEMP_DIR}/cmake-${VERSION}"
fi

# 2. Determine archive filename, binary subpath, and binary extension
BIN_EXT=""
case "${OS}" in
  Linux)
    case "${ARCH}" in
      X64)   ARCH_NAME="x86_64" ;;
      ARM64) ARCH_NAME="aarch64" ;;
      *) echo "::error::Unsupported Linux architecture: ${ARCH}"; exit 1 ;;
    esac
    ARCHIVE="cmake-${VERSION}-linux-${ARCH_NAME}.tar.gz"
    BIN_SUBPATH="bin"
    ;;
  macOS)
    ARCHIVE="cmake-${VERSION}-macos-universal.tar.gz"
    BIN_SUBPATH="CMake.app/Contents/bin"
    ;;
  Windows)
    case "${ARCH}" in
      X64)   ARCH_NAME="x86_64" ;;
      ARM64) ARCH_NAME="arm64" ;;
      *) echo "::error::Unsupported Windows architecture: ${ARCH}"; exit 1 ;;
    esac
    ARCHIVE="cmake-${VERSION}-windows-${ARCH_NAME}.zip"
    BIN_SUBPATH="bin"
    BIN_EXT=".exe"
    ;;
  *)
    echo "::error::Unsupported OS: ${OS}"
    exit 1
    ;;
esac

ARCHIVE_URL="https://github.com/Kitware/CMake/releases/download/v${VERSION}/${ARCHIVE}"
ARCHIVE_PATH="${TEMP_DIR}/${ARCHIVE}"

# 3. Download
echo "==> Downloading ${ARCHIVE_URL}..."
curl -fsSL --retry 3 -o "${ARCHIVE_PATH}" "${ARCHIVE_URL}"

# 4. Verify SHA-256 directly in one step
echo "==> Verifying SHA-256..."
CHECK_CMD=$(command -v sha256sum || echo "shasum -a 256")
echo "${EXPECTED_SHA}  ${ARCHIVE_PATH}" | ${CHECK_CMD} -c -

# 5. Extract into destination directory
echo "==> Extracting into ${DEST_DIR}..."
mkdir -p "${DEST_DIR}"

if [[ "${ARCHIVE}" == *.tar.gz ]]; then
  tar -xzf "${ARCHIVE_PATH}" -C "${DEST_DIR}" --strip-components=1
elif [[ "${ARCHIVE}" == *.zip ]]; then
  UNZIP_TEMP="${TEMP_DIR}/unzip_tmp"
  mkdir -p "${UNZIP_TEMP}"
  unzip -q -o "${ARCHIVE_PATH}" -d "${UNZIP_TEMP}"
  TOP_DIR=$(find "${UNZIP_TEMP}" -mindepth 1 -maxdepth 1 -type d)
  mv "${TOP_DIR}"/* "${DEST_DIR}/"
  rm -rf "${UNZIP_TEMP}"
fi
rm -f "${ARCHIVE_PATH}"

# 6. Set PATH and GITHUB_OUTPUT
CMAKE_BIN_DIR="${DEST_DIR}/${BIN_SUBPATH}"
echo "${CMAKE_BIN_DIR}" >> "${GITHUB_PATH}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "cmake-dir=${CMAKE_BIN_DIR}"
    echo "cmake-path=${CMAKE_BIN_DIR}/cmake${BIN_EXT}"
    echo "ctest-path=${CMAKE_BIN_DIR}/ctest${BIN_EXT}"
  } >> "${GITHUB_OUTPUT}"
fi

echo "==> CMake ${VERSION} successfully installed at ${CMAKE_BIN_DIR}"

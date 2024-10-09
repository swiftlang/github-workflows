#!/bin/bash
# ===----------------------------------------------------------------------===//
#
# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See https://swift.org/LICENSE.txt for license information
# See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
#
# ===----------------------------------------------------------------------===//

set -euo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

REPO_ROOT="$(git -C "$PWD" rev-parse --show-toplevel)"

log "Checking for local swift dependencies..."
read -ra PATHS_TO_CHECK <<< "$( \
  git -C "${REPO_ROOT}" ls-files -z \
  "Package.swift" \
  | xargs -0 \
)"

for FILE_PATH in "${PATHS_TO_CHECK[@]}"; do
    if [[ $(grep ".package(path:" "${FILE_PATH}" -c) -ne 0 ]] ; then
        fatal "❌ The '${FILE_PATH}' file contains local Swift package reference(s)."
    fi
done 

log "✅ Found 0 local Swift package dependency references."
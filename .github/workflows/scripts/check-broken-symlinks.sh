#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2024 Apple Inc. and the Swift project authors
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

log "Checking for broken symlinks..."
num_broken_symlinks=0
while read -r -d '' file; do
  if ! test -e "./${file}"; then
    error "Broken symlink: ${file}"
    ((num_broken_symlinks++))
  fi
done < <(git ls-files -z)

if [ "${num_broken_symlinks}" -gt 0 ]; then
  fatal "❌ Found ${num_broken_symlinks} symlinks."
fi

log "✅ Found 0 symlinks."

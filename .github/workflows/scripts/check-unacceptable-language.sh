#!/bin/bash
## ===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2024 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
## ===----------------------------------------------------------------------===##

set -euo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

test -n "${UNACCEPTABLE_WORD_LIST:-}" || fatal "UNACCEPTABLE_WORD_LIST unset"

unacceptable_language_lines=
if [[ -f .unacceptablelanguageignore ]]; then
    log "Found for unacceptable file..."
    log "Checking for unacceptable language..."
    unacceptable_language_lines=$(tr '\n' '\0' < .unacceptablelanguageignore | xargs -0 -I% printf '":(exclude)%" '| xargs git grep -i -I -w -H -n --column -E "${UNACCEPTABLE_WORD_LIST// /|}" | grep -v "ignore-unacceptable-language") || true | /usr/bin/paste -s -d " " -
else
    log "Checking for unacceptable language..."
    unacceptable_language_lines=$(git grep -i -I -w -H -n --column -E "${UNACCEPTABLE_WORD_LIST// /|}" | grep -v "ignore-unacceptable-language") || true | /usr/bin/paste -s -d " " -
fi

if [ -n "${unacceptable_language_lines}" ]; then
    fatal " ❌ Found unacceptable language:
${unacceptable_language_lines}
"
fi


log "✅ Found no unacceptable language."
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

if [ -f .license_header_template ]; then
  # allow projects to override the license header template
  expected_file_header_template=$(cat .license_header_template)
else
  test -n "${PROJECT_NAME:-}" || fatal "PROJECT_NAME unset"
  expected_file_header_template="@@===----------------------------------------------------------------------===@@
@@
@@ This source file is part of the ${PROJECT_NAME} open source project
@@
@@ Copyright (c) YEARS Apple Inc. and the ${PROJECT_NAME} project authors
@@ Licensed under Apache License v2.0
@@
@@ See LICENSE.txt for license information
@@ See CONTRIBUTORS.txt for the list of ${PROJECT_NAME} project authors
@@
@@ SPDX-License-Identifier: Apache-2.0
@@
@@===----------------------------------------------------------------------===@@"
fi

paths_with_missing_license=( )

if [[ -f .licenseignore ]]; then
  static_exclude_list='":(exclude).licenseignore" ":(exclude).license_header_template" '
  dynamic_exclude_list=$(tr '\n' '\0' < .licenseignore | xargs -0 -I% printf '":(exclude)%" ')
  exclude_list=$static_exclude_list$dynamic_exclude_list
else
  exclude_list=":(exclude).license_header_template"
fi

file_paths=$(echo "$exclude_list" | xargs git ls-files)

while IFS= read -r file_path; do
  file_basename=$(basename -- "${file_path}")
  file_extension="${file_basename##*.}"
  if [[ -L "${file_path}" ]]; then
    continue  # Ignore symbolic links
  fi

  # The characters that are used to start a line comment and that replace '@@' in the license header template
  comment_marker=''
  # A line that we expect before the license header. This should end with a newline if it is not empty
  header_prefix=''
  # shellcheck disable=SC2001 # We prefer to use sed here instead of bash search/replace
  case "${file_extension}" in
    bazel) comment_marker='##' ;;
    bazelrc) comment_marker='##' ;;
    bzl) comment_marker='##' ;;
    c) comment_marker='//' ;;
    cpp) comment_marker='//' ;;
    cmake) comment_marker='##' ;;
    code-workspace) continue ;;  # VS Code workspaces are JSON and shouldn't contain comments
    CODEOWNERS) continue ;;  # Doesn't need a license header
    Dockerfile) comment_marker='##' ;;
    editorconfig) comment_marker='##' ;;
    flake8) continue ;; # Configuration file doesn't need a license header
    gitattributes) continue ;; # Configuration files don't need license headers
    gitignore) continue ;; # Configuration files don't need license headers
    gradle) comment_marker='//' ;;
    groovy) comment_marker='//' ;;
    gyb) comment_marker='//' ;;
    h) comment_marker='//' ;;
    in) comment_marker='##' ;;
    java) comment_marker='//' ;;
    js) comment_marker='//' ;;
    json) continue ;; # JSON doesn't support line comments
    jsx) comment_marker='//' ;;
    kts) comment_marker='//' ;;
    md) continue ;; # Text files don't need license headers
    mobileconfig) continue ;; # Doesn't support comments
    modulemap) continue ;; # Configuration file doesn't need a license header
    plist) continue ;; # Plists don't support line comments
    proto) comment_marker='//' ;;
    ps1) comment_marker='##' ;;
    py) comment_marker='##'; header_prefix=$'#!/usr/bin/env python3\n' ;;
    rb) comment_marker='##'; header_prefix=$'#!/usr/bin/env ruby\n' ;;
    sh) comment_marker='##'; header_prefix=$'#!/bin/bash\n' ;;
    strings) comment_marker='//' ;;
    swift-format) continue ;; # .swift-format is JSON and doesn't support comments
    swift) comment_marker='//' ;;
    ts) comment_marker='//' ;;
    tsx) comment_marker='//' ;;
    txt) continue ;; # Text files don't need license headers
    yml) continue ;; # YAML Configuration files don't need license headers
    yaml) continue ;; # YAML Configuration files don't need license headers
    xcbuildrules) comment_marker='//' ;;
    xcspec) comment_marker='//' ;;
    *)
      error "Unsupported file extension ${file_extension} for file (exclude or update this script): ${file_path}"
      paths_with_missing_license+=("${file_path} ")
      continue
      ;;
  esac
  expected_file_header=$(echo "${header_prefix}${expected_file_header_template}" | sed -e "s|@@|$comment_marker|g")
  expected_file_header_linecount=$(echo "${expected_file_header}" | wc -l)

  file_header=$(head -n "${expected_file_header_linecount}" "${file_path}")
  normalized_file_header=$(
    echo "${file_header}" \
    | sed -E -e 's/20[12][0123456789] ?- ?20[12][0123456789]/YEARS/' -e 's/20[12][0123456789]/YEARS/' \
  )

  if ! diff -u \
    --label "Expected header" <(echo "${expected_file_header}") \
    --label "${file_path}" <(echo "${normalized_file_header}")
  then
    paths_with_missing_license+=("${file_path} ")
  fi
done <<< "$file_paths"

if [ "${#paths_with_missing_license[@]}" -gt 0 ]; then
  fatal "❌ Found missing license header in files: ${paths_with_missing_license[*]}."
fi

log "✅ Found no files with missing license header."

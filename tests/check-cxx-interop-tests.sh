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

# Tests that check-cxx-interop.sh refuses a package it cannot check and hands its
# arguments to the build.
#
# The check works by importing the package's library products from a package built in
# Cxx interoperability mode. A package with none to import compiles nothing, so a green
# check would mean the interoperability build never ran; and an argument that never
# reaches the compiler takes -Xswiftc -warnings-as-errors with it.
#
# swift is stubbed, so the tests need no toolchain. The assertions on tests/TestPackage
# read its manifests directly for that reason, and ask a real toolchain for the products
# it reports only when there is one.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/workflows/scripts/check-cxx-interop.sh"

failures=0

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

STUB_DIR="$WORKDIR/stubs"
PACKAGE_DIR="$WORKDIR/package"
mkdir -p "$STUB_DIR" "$PACKAGE_DIR"

export STUB_MANIFEST="$WORKDIR/manifest.json"
export STUB_BUILD_ARGUMENTS="$WORKDIR/build-arguments.txt"
export STUB_BUILD_DIRECTORY="$WORKDIR/build-directory.txt"

# Stands in for the toolchain: reports the manifest the test asked for, lays out what
# `swift package init` would, and records the build's arguments and directory.
cat >"$STUB_DIR/swift" <<'STUB'
#!/bin/bash
case "$1 ${2:-}" in
    "package dump-package")
        cat "$STUB_MANIFEST"
        ;;
    "package init")
        name=$(basename "$PWD")
        mkdir -p "Sources/$name"
        : >"Sources/$name/$name.swift"
        printf 'let package = Package(name: "%s")\n' "$name" >Package.swift
        ;;
    "build "*|"build ")
        shift
        printf '%s\n' "$@" >"$STUB_BUILD_ARGUMENTS"
        printf '%s\n' "$PWD" >"$STUB_BUILD_DIRECTORY"
        ;;
esac
STUB
chmod +x "$STUB_DIR/swift"

# run_check <manifest_json> [argument ...] - echoes the exit status; the combined output
# is left in $CHECK_LOG.
CHECK_LOG="$WORKDIR/check.log"
run_check() {
    local manifest="$1"
    shift
    printf '%s\n' "$manifest" >"$STUB_MANIFEST"
    rm -f "$STUB_BUILD_ARGUMENTS" "$STUB_BUILD_DIRECTORY"
    (
        cd "$PACKAGE_DIR" || exit 1
        PATH="$STUB_DIR:$PATH" "$SCRIPT" "$@" >"$CHECK_LOG" 2>&1
    )
    echo "$?"
}

assert_status() {
    local what="$1" expected="$2" actual="$3"
    if [[ "$expected" != "$actual" ]]; then
        echo "  FAIL $what: expected exit $expected, got $actual"
        failures=$((failures + 1))
    else
        echo "  ok   $what"
    fi
}

assert_contains() {
    local what="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  FAIL $what: [$needle] not found in [$haystack]"
        failures=$((failures + 1))
    else
        echo "  ok   $what"
    fi
}

# An executable product is not importable, so a package holding only one is as
# uncheckable as a package with no products at all.
no_products='{"name":"Fixture","products":[]}'
executable_only='{"name":"Fixture","products":[{"name":"tool","type":{"executable":null}}]}'
with_library='{"name":"Fixture","products":[{"name":"Lib","type":{"library":["automatic"]}},{"name":"tool","type":{"executable":null}}]}'

assert_status "a package with no products is refused" "1" "$(run_check "$no_products")"
assert_contains "the refusal says what is wrong" "No library products" "$(cat "$CHECK_LOG")"
assert_status "a package with only an executable product is refused" "1" \
    "$(run_check "$executable_only")"

assert_status "a package with a library product is checked" "0" \
    "$(run_check "$with_library" -Xswiftc -warnings-as-errors)"
assert_contains "the arguments reach the build" $'-Xswiftc\n-warnings-as-errors' \
    "$(cat "$STUB_BUILD_ARGUMENTS")"

build_directory=$(cat "$STUB_BUILD_DIRECTORY")
assert_contains "the library product is depended on" \
    '.product(name: "Lib", package: "Fixture")' "$(cat "$build_directory/Package.swift")"
assert_contains "the library product is imported" "import Lib" \
    "$(cat "$build_directory/Sources/$(basename "$build_directory")/$(basename "$build_directory").swift")"
rm -rf "$build_directory"

# The repository checks itself against tests/TestPackage, so every manifest the fixture
# offers has to declare a library product. dump-package is the authoritative answer but
# only speaks for the manifest the toolchain at hand selects.
for manifest_file in "$REPO_ROOT"/tests/TestPackage/Package*.swift; do
    if grep -q '\.library(' "$manifest_file"; then
        echo "  ok   $(basename "$manifest_file") declares a library product"
    else
        echo "  FAIL $(basename "$manifest_file") declares no library product, so the self-test checks nothing"
        failures=$((failures + 1))
    fi
done

if ! command -v swift >/dev/null 2>&1; then
    echo "  skip tests/TestPackage library products (no swift on PATH)"
elif ! fixture_manifest=$(cd "$REPO_ROOT/tests/TestPackage" && swift package dump-package 2>&1); then
    echo "  skip tests/TestPackage library products (swift package dump-package failed)"
else
    fixture_products=$(echo "$fixture_manifest" | jq -r '[.products[] | select(.type.library != null) | .name] | join(" ")')
    if [[ -n "$fixture_products" ]]; then
        echo "  ok   tests/TestPackage reports library products ($fixture_products)"
    else
        echo "  FAIL tests/TestPackage reports no library product, so the self-test checks nothing"
        failures=$((failures + 1))
    fi
fi

if [[ "$failures" -gt 0 ]]; then
    printf '\n%d failed\n' "$failures"
    exit 1
fi
printf '\nall passed\n'

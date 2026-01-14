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

ANDROID_PROFILE="Nexus 10"
ANDROID_EMULATOR_TIMEOUT=300

SWIFTPM_HOME="${XDG_CONFIG_HOME}"/swiftpm
# e.g., "${SWIFTPM_HOME}"/swift-sdks/swift-DEVELOPMENT-SNAPSHOT-2025-12-11-a_android.artifactbundle/
SWIFT_ANDROID_SDK_HOME=$(find "${SWIFTPM_HOME}"/swift-sdks -maxdepth 1 -name 'swift-*android.artifactbundle' | tail -n 1)

ANDROID_SDK_TRIPLE="x86_64-unknown-linux-android28"

while [[ $# -gt 0 ]]; do
    case $1 in
        --android-sdk-triple=*)
            ANDROID_SDK_TRIPLE="${1#*=}"
            shift
            ;;
        --android-profile=*)
            ANDROID_PROFILE="${1#*=}"
            shift
            ;;
        --android-emulator-timeout=*)
            ANDROID_EMULATOR_TIMEOUT="${1#*=}"
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

# extract the API level from the end of the triple 
ANDROID_API="${ANDROID_SDK_TRIPLE/*-unknown-linux-android/}"

# extract the build arch from the beginning of the triple
ANDROID_EMULATOR_ARCH="${ANDROID_SDK_TRIPLE/-unknown-linux-android*/}"

# x86_64=x86_64, armv7=arm
ANDROID_EMULATOR_ARCH_TRIPLE="${ANDROID_EMULATOR_ARCH}"

log "Running tests for ${ANDROID_SDK_TRIPLE}"

EMULATOR_SPEC="system-images;android-${ANDROID_API};default;${ANDROID_EMULATOR_ARCH}"

log "SWIFT_ANDROID_SDK_HOME=${SWIFT_ANDROID_SDK_HOME}"

# install and start an Android emulator
log "Listing installed Android SDKs"
export PATH="${PATH}:$ANDROID_HOME/emulator:$ANDROID_HOME/tools:$ANDROID_HOME/build-tools/latest:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"
sdkmanager --list_installed

log "Updating Android SDK licenses"
yes | sdkmanager --licenses > /dev/null || true

log "Installing Android emulator"
sdkmanager --install "emulator" "platform-tools" "platforms;android-${ANDROID_API}" "${EMULATOR_SPEC}"

log "Creating Android emulator"
export ANDROID_AVD_HOME=${XDG_CONFIG_HOME:-$HOME}/.android/avd
ANDROID_EMULATOR_NAME="swiftemu"
avdmanager create avd --force -n "${ANDROID_EMULATOR_NAME}" --package "${EMULATOR_SPEC}" --device "${ANDROID_PROFILE}"

log "Configuring Android emulators"
emulator -list-avds

log "Check Hardware Acceleration (KVM)"
emulator -accel-check

log "Starting Android emulator"
# launch the emulator in the background
nohup emulator -no-metrics -partition-size 1024 -memory 4096 -wipe-data -no-window -no-snapshot -noaudio -no-boot-anim -avd "${ANDROID_EMULATOR_NAME}" &

# wait briefly before starting to poll the emulator
sleep 10

log "Waiting for Android emulator startup"
EMULATOR_CHECK_SECONDS_ELAPSED=0
EMULATOR_CHECK_INTERVAL=5 # Seconds between status checks
while true; do
    # Check if the boot is completed
    # 'adb shell getprop sys.boot_completed' returns 1 when done
    # Ignore failure status since it will fail with "adb: device offline"
    adb shell getprop sys.boot_completed || true
    BOOT_STATUS=$(adb shell getprop sys.boot_completed || true 2>/dev/null | tr -d '\r')

    if [ "$BOOT_STATUS" == "1" ]; then
        log "Emulator is ready"
        break;
    fi

    if [ "$EMULATOR_CHECK_SECONDS_ELAPSED" -ge "$ANDROID_EMULATOR_TIMEOUT" ]; then
        fatal "Timeout reached ($ANDROID_EMULATOR_TIMEOUT seconds). Aborting."
    fi

    sleep "$EMULATOR_CHECK_INTERVAL"
    ((EMULATOR_CHECK_SECONDS_ELAPSED+=EMULATOR_CHECK_INTERVAL))
done

log "Prepare Swift test package"
# create a staging folder where we copy the test executable
# and all the dependent libraries to copy over to the emulator
STAGING_DIR="swift-android-test"
rm -rf "${STAGING_DIR}"
mkdir "${STAGING_DIR}"

BUILD_DIR=.build/"${ANDROID_SDK_TRIPLE}"/debug

find "${BUILD_DIR}" -name '*.xctest' -exec cp -av {} "${STAGING_DIR}" \;
find "${BUILD_DIR}" -name '*.resources' -exec cp -av {} "${STAGING_DIR}" \;

# copy over the required library dependencies
cp -av "${SWIFT_ANDROID_SDK_HOME}"/swift-android/swift-resources/usr/lib/swift-"${ANDROID_EMULATOR_ARCH_TRIPLE}"/android/*.so "${STAGING_DIR}"
cp -av "${SWIFT_ANDROID_SDK_HOME}"/swift-android/ndk-sysroot/usr/lib/"${ANDROID_EMULATOR_ARCH_TRIPLE}"-linux-android/libc++_shared.so "${STAGING_DIR}"

# for the common case of tests referencing
# their own files as hardwired paths instead of resources
if [[ -d Tests ]]; then
    cp -a Tests "${STAGING_DIR}"
fi

# warn about macros in packages, as per
# https://github.com/swiftlang/github-workflows/pull/215#discussion_r2621335245
! grep -lq '\.macro(' Package.swift || log "WARNING: Packages with macros are known to have issues with cross-compilation: https://github.com/swiftlang/swift-package-manager/issues/8094"

log "Copy Swift test package to emulator"

ANDROID_TMP_FOLDER="/data/local/tmp/${STAGING_DIR}"
adb push "${STAGING_DIR}" "${ANDROID_TMP_FOLDER}"

TEST_CMD="./*.xctest"
TEST_SHELL="cd ${ANDROID_TMP_FOLDER}"
TEST_SHELL="${TEST_SHELL} && ${TEST_CMD} --testing-library xctest"

# Run test cases a second time with the Swift Testing library
# We additionally need to handle the special exit code
# EXIT_NO_TESTS_FOUND (69 on Android), which can happen
# when the tests link to Testing, but no tests are executed
# see: https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Commands/SwiftTestCommand.swift#L1571
TEST_SHELL="${TEST_SHELL} && ${TEST_CMD} --testing-library swift-testing && [ \$? -eq 0 ] || [ \$? -eq 69 ]"

log "Run Swift package tests"

# run the test executable
adb shell "${TEST_SHELL}"

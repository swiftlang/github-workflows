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

EMULATOR_NAME="swiftemu"
ANDROID_PROFILE="Nexus 10"
ANDROID_EMULATOR_LAUNCH_TIMEOUT=300

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
avdmanager create avd --force -n "${EMULATOR_NAME}" --package "${EMULATOR_SPEC}" --device "${ANDROID_PROFILE}"

log "Configuring Android emulators"
emulator -list-avds

log "Check Hardware Acceleration (KVM)"
emulator -accel-check

log "Starting Android emulator"
# launch the emulator in the background
nohup emulator -no-metrics -partition-size 1024 -memory 4096 -wipe-data -no-window -no-snapshot -noaudio -no-boot-anim -avd "${EMULATOR_NAME}" &

log "Waiting for Android emulator startup"
timeout ${ANDROID_EMULATOR_LAUNCH_TIMEOUT} adb wait-for-any-device

log "Prepare Swift test package"
# create a staging folder where we copy the test executable
# and all the dependent libraries to copy over to the emulator
STAGING_DIR="swift-android-test"
rm -rf .build/"${STAGING_DIR}"
mkdir .build/"${STAGING_DIR}"

# for the common case of tests referencing
# their own files as hardwired resource paths
if [[ -d Tests ]]; then
    cp -a Tests .build/"${STAGING_DIR}"
fi

pushd .build/

TEST_PACKAGE=$(find debug/ -name '*.xctest' | tail -n 1 | xargs basename)
cp -a debug/"${TEST_PACKAGE}" "${STAGING_DIR}"
find debug/ -name '*.resources' -exec cp -a {} "${STAGING_DIR}" \;
cp -a "${SWIFT_ANDROID_SDK_HOME}"/swift-android/swift-resources/usr/lib/swift-"${ANDROID_EMULATOR_ARCH_TRIPLE}"/android/*.so "${STAGING_DIR}"
cp -a "${SWIFT_ANDROID_SDK_HOME}"/swift-android/ndk-sysroot/usr/lib/"${ANDROID_EMULATOR_ARCH_TRIPLE}"-linux-android/libc++_shared.so "${STAGING_DIR}"

log "Copy Swift test package to emulator"

ANDROID_TMP_FOLDER="/data/local/tmp/${STAGING_DIR}"
adb push "${STAGING_DIR}" "${ANDROID_TMP_FOLDER}"

popd

TEST_CMD="./${TEST_PACKAGE}"
TEST_SHELL="cd ${ANDROID_TMP_FOLDER}"
TEST_SHELL="${TEST_SHELL} && ${TEST_CMD}"

# Run test cases a second time with the Swift Testing library
# We additionally need to handle the special exit code EXIT_NO_TESTS_FOUND (69 on Android),
# which can happen when the tests link to Testing, but no tests are executed
# see: https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Commands/SwiftTestCommand.swift#L1571
TEST_SHELL="${TEST_SHELL} && ${TEST_CMD} --testing-library swift-testing && [ \$? -eq 0 ] || [ \$? -eq 69 ]"

log "Run Swift package tests"

# run the test executable
adb shell "${TEST_SHELL}"

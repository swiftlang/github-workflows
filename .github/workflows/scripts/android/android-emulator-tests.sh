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

ANDROID_API=28
ANDROID_EMULATOR_ARCH="x86_64"
EMULATOR_SPEC="system-images;android-${ANDROID_API};default;${ANDROID_EMULATOR_ARCH}"
EMULATOR_NAME="swiftemu"
ANDROID_PROFILE="Pixel 6"

# see if the Android SDK is even installed
echo "CHECKING FOR ANDROID SDK"
find / -type f -name sdkmanager || true
echo "DONE CHECKING FOR ANDROID SDK"

# install and start an Android emulator
sdkmanager --list_installed
yes | sdkmanager --licenses > /dev/null
sdkmanager --install "${EMULATOR_SPEC}" "emulator" "platform-tools" "platforms;android-${ANDROID_API}"
avdmanager create avd -n "${EMULATOR_NAME}" -k "${EMULATOR_SPEC}" --device "${ANDROID_PROFILE}"
emulator -list-avds
# launch the emulator in the background; we will cat the logs at the end
nohup emulator -memory 4096 -avd "${EMULATOR_NAME}" -wipe-data -no-window -no-snapshot -noaudio -no-boot-anim 2>&1 > emulator.log &
adb logcat 2>&1 > logcat.log &

# create a staging folder where we copy the test executable
# and all the dependent libraries to copy over to the emulator
STAGING="android-test-${PACKAGE}"
rm -rf .build/"${STAGING}"
mkdir .build/"${STAGING}"

# for the common case of tests referencing their own files as hardwired resource paths
if [[ -d Tests ]]; then
    cp -a Tests .build/"${STAGING}"
fi

cd .build/
cp -a debug/*.xctest "${STAGING}"
cp -a debug/*.resources "${STAGING}" || true
cp -a ${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/*/sysroot/usr/lib/${ANDROID_EMULATOR_ARCH_TRIPLE}-linux-android/libc++_shared.so "${STAGING}"
cp -a ${SWIFT_ANDROID_SDK_HOME}/swift-android/swift-resources/usr/lib/swift-${ANDROID_EMULATOR_ARCH_TRIPLE}/android/*.so "${STAGING}"

adb push ${STAGING} /data/local/tmp/

cd -

TEST_CMD="./${PACKAGE}PackageTests.xctest"
TEST_SHELL="cd /data/local/tmp/${STAGING}"
TEST_SHELL="${TEST_SHELL} && ${TEST_CMD}"

# Run test cases a second time with the Swift Testing library
# We additionally need to handle the special exit code EXIT_NO_TESTS_FOUND (69 on Android),
# which can happen when the tests link to Testing, but no tests are executed
# see: https://github.com/swiftlang/swift-package-manager/blob/1b593469e8ad3daf2cc10e798340bd2de68c402d/Sources/Commands/SwiftTestCommand.swift#L1542
TEST_SHELL="${TEST_SHELL} && ${TEST_CMD} --testing-library swift-testing && [ \$? -eq 0 ] || [ \$? -eq 69 ]"

# run the test executable
adb shell "${TEST_SHELL}"


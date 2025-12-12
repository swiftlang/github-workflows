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
ANDROID_PROFILE="Nexus 10"

install_package() {
    # Detect package manager
    if command -v apt >/dev/null 2>&1; then
        INSTALL_PACKAGE_COMMAND="apt update -q && apt install -yq"
    elif command -v dnf >/dev/null 2>&1; then
        INSTALL_PACKAGE_COMMAND="dnf install -y"
    elif command -v yum >/dev/null 2>&1; then
        INSTALL_PACKAGE_COMMAND="yum install -y"
    else
        fatal "No supported package manager found"
    fi
    eval "$INSTALL_PACKAGE_COMMAND $1"
}

command -v curl >/dev/null || install_package curl

# /usr/lib/jvm/java-17-openjdk-amd64
log "Installing Java"
# Java packages are named different things on different distributions
install_package java-17-openjdk-devel || install_package openjdk-17-jdk || install_package java-openjdk17 || install_package java-17-amazon-corretto
log "JAVA_HOME: ${JAVA_HOME}" || true
which java || true

# TODO: java-17-amazon-corretto does not add to JAVA_HOME
log "Checking: /usr/lib/jvm/"
ls /usr/lib/jvm/ || true
log "Checking: /usr/lib/jvm/java-17-amazon-corretto.x86_64"
ls /usr/lib/jvm/java-17-amazon-corretto.x86_64 || true

# download and install the Android SDK
log "Installing Android cmdline-tools"
mkdir ~/android-sdk
pushd ~/android-sdk
export ANDROID_HOME=${PWD}
curl --connect-timeout 30 --retry 3 --retry-delay 2 --retry-max-time 60 -fsSL -o commandlinetools.zip https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
unzip commandlinetools.zip
mv cmdline-tools latest
mkdir cmdline-tools
mv latest cmdline-tools
export PATH=${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/emulator:${ANDROID_HOME}/tools:${ANDROID_HOME}/build-tools/latest:${ANDROID_HOME}/platform-tools:${PATH}
popd

# install and start an Android emulator

log "Listing installed Android SDKs"
sdkmanager --list_installed

log "Updating Android licenses"
yes | sdkmanager --licenses > /dev/null || true

log "Installing Android emulator"
sdkmanager --install "${EMULATOR_SPEC}" "emulator" "platform-tools" "platforms;android-${ANDROID_API}"

log "Creating Android emulator"
avdmanager create avd -n "${EMULATOR_NAME}" -k "${EMULATOR_SPEC}" --device "${ANDROID_PROFILE}"
emulator -list-avds

log "Enable KVM"
# enable KVM on Linux, else error on emulator launch:
# CPU acceleration status: This user doesn't have permissions to use KVM (/dev/kvm).
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm

log "Starting Android emulator"
# launch the emulator in the background; we will cat the logs at the end
nohup emulator -memory 4096 -avd "${EMULATOR_NAME}" -wipe-data -no-window -no-snapshot -noaudio -no-boot-anim &
#2>&1 > emulator.log &

#adb logcat 2>&1 > logcat.log &

log "Waiting for Android emulator startup"
adb wait-for-any-device

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


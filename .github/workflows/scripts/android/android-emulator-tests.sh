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
# x86_64=x86_64, armv7=arm
ANDROID_EMULATOR_ARCH_TRIPLE="${ANDROID_EMULATOR_ARCH}"
EMULATOR_SPEC="system-images;android-${ANDROID_API};default;${ANDROID_EMULATOR_ARCH}"
EMULATOR_NAME="swiftemu"
ANDROID_PROFILE="Nexus 10"
ANDROID_EMULATOR_LAUNCH_TIMEOUT=300

SWIFTPM_HOME=/root/.swiftpm
# e.g., "${SWIFTPM_HOME}"/swift-sdks/swift-DEVELOPMENT-SNAPSHOT-2025-12-11-a_android.artifactbundle/
SWIFT_ANDROID_SDK_HOME=$(find "${SWIFTPM_HOME}"/swift-sdks -maxdepth 1 -name 'swift-*android.artifactbundle' | tail -n 1)
ANDROID_NDK_HOME="${SWIFTPM_HOME}"/android-ndk-r27d

log "SWIFT_ANDROID_SDK_HOME=${SWIFT_ANDROID_SDK_HOME}"
log "ANDROID_NDK_HOME=${ANDROID_NDK_HOME}"

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
command -v sudo >/dev/null || install_package sudo

log "Show Disk Space"
df -h

# /usr/lib/jvm/java-17-openjdk-amd64
log "Installing Java"
# Java packages are named different things on different distributions
command -v java >/dev/null || install_package java-17-openjdk-devel || install_package openjdk-17-jdk || install_package java-openjdk17 || install_package java-17-amazon-corretto

export PATH=${PATH}:/usr/lib/jvm/java/bin:/usr/lib/jvm/jre/bin
command -v java

#log "Installing KVM"
###install_package qemu-kvm || install_package kvm || install_package @virt
# https://help.ubuntu.com/community/KVM/Installation
#install_package qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
#sudo adduser "$(id -un)" libvirt || true
#sudo adduser "$(id -un)" kvm || true
#virsh list --all || true
#ls -la /var/run/libvirt/libvirt-sock || true
#ls -l /dev/kvm || true
#rmmod kvm || true
#modprobe -a kvm || true
#ls /etc/udev/rules.d/99-kvm4all.rules || true

# download and install the Android SDK
log "Installing Android cmdline-tools"
mkdir ~/android-sdk
pushd ~/android-sdk
export ANDROID_HOME=${PWD}

curl --connect-timeout 30 --retry 3 --retry-delay 2 --retry-max-time 60 -fsSL -o commandlinetools.zip https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
unzip commandlinetools.zip
rm commandlinetools.zip
# a quirk of the archive is that its root is cmdline-tools,
# but when executed they are expected to be at cmdline-tools/latest
# or else the other relative paths are not identified correctly
mv cmdline-tools latest
mkdir cmdline-tools
mv latest cmdline-tools
export PATH=${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/emulator:${ANDROID_HOME}/tools:${ANDROID_HOME}/build-tools/latest:${ANDROID_HOME}/platform-tools:${PATH}
export ANDROID_SDK_HOME=${ANDROID_HOME}
export ANDROID_AVD_HOME=${ANDROID_SDK_HOME}/avd
popd

# install and start an Android emulator

log "Listing installed Android SDKs"
sdkmanager --list_installed

log "Updating Android SDK licenses"
yes | sdkmanager --licenses > /dev/null || true

log "Installing Android emulator"
sdkmanager --install "emulator" "platform-tools" "platforms;android-${ANDROID_API}" "${EMULATOR_SPEC}"

log "Creating Android emulator"
avdmanager create avd --force -n "${EMULATOR_NAME}" --package "${EMULATOR_SPEC}" --device "${ANDROID_PROFILE}"

find "${ANDROID_AVD_HOME}" || true
find "~/.android" || true

ANDROID_AVD_CONFIG="${ANDROID_AVD_HOME}"/"${EMULATOR_NAME}".avd/config.ini
mkdir -p "$(dirname ${ANDROID_AVD_CONFIG})"
# ~2G partition size
echo 'disk.dataPartition.size=1024MB' >> "${ANDROID_AVD_CONFIG}"
log "Checking Android emulator"
find "${ANDROID_AVD_HOME}"

log "Listing Android emulators"
emulator -list-avds

log "Enable KVM"
emulator -accel-check || true

# enable KVM on Linux, else error on emulator launch:
# CPU acceleration status: This user doesn't have permissions to use KVM (/dev/kvm).
#echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
#sudo udevadm control --reload-rules
#sudo udevadm trigger --name-match=kvm
#emulator -accel-check

log "Show Disk Space"
df -h

log "Starting Android emulator"

# launch the emulator in the background
# -no-accel disables the need for KVM, but is very slow
nohup emulator -no-accel -no-metrics -partition-size 1024 -memory 4096 -wipe-data -no-window -no-snapshot -noaudio -no-boot-anim -avd "${EMULATOR_NAME}" &

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
cp -a "${ANDROID_NDK_HOME}"/toolchains/llvm/prebuilt/*/sysroot/usr/lib/"${ANDROID_EMULATOR_ARCH_TRIPLE}"-linux-android/libc++_shared.so "${STAGING_DIR}"

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

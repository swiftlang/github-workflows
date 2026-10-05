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
. $PSScriptRoot\install-swift.ps1

if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") {
    $SWIFT='https://download.swift.org/swift-6.4.0-release/windows10-arm64/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-windows10-arm64.exe'
    $SWIFT_SHA256='f48e393634995cb589f547e40d64673bc641ca76b099697ba8227a8904be4a49'
} else {
    $SWIFT='https://download.swift.org/swift-6.4.0-release/windows10/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-windows10.exe'
    $SWIFT_SHA256='76169a85bcba82854a0cd8f9655ffb74b3758d60c35a245457510095f2823c03'
}

Install-Swift -Url $SWIFT -Sha256 $SWIFT_SHA256

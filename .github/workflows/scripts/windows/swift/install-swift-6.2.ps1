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
. $PSScriptRoot\install-swift.ps1

if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") {
    $SWIFT='https://download.swift.org/swift-6.2.1-release/windows10-arm64/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE-windows10-arm64.exe'
    $SWIFT_SHA256='7c2351e1708f6e74f4c97098c50ac049e08a58894e75cc7c8fd220eb2549fb9d'
} else {
    $SWIFT='https://download.swift.org/swift-6.2.1-release/windows10/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE-windows10.exe'
    $SWIFT_SHA256='FD1209AC3E008152924E0409E5590F2FE41644132E532D4526B8641339E88000'
}

Install-Swift -Url $SWIFT -Sha256 $SWIFT_SHA256

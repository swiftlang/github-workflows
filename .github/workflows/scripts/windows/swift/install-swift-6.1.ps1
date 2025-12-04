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
    $SWIFT='https://download.swift.org/swift-6.1.2-release/windows10-arm64/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10-arm64.exe'
    $SWIFT_SHA256='121fb407e578178f82dccf39a4d03527873d8f7611a801a8fc26da52503a0c5c'
} else {
    $SWIFT='https://download.swift.org/swift-6.1.2-release/windows10/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-windows10.exe'
    $SWIFT_SHA256='92a0323ed7dd333c3b05e6e0e428f3a91c77d159f6ccfc8626a996f2ace09a0b'
}

Install-Swift -Url $SWIFT -Sha256 $SWIFT_SHA256

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
    $SWIFT='https://download.swift.org/swift-6.3-release/windows10-arm64/swift-6.3-RELEASE/swift-6.3-RELEASE-windows10-arm64.exe'
    $SWIFT_SHA256='eca190022838d48984d04f8fdedef613e6252f694df2079e7eb6c4137b8bbdac'
} else {
    $SWIFT='https://download.swift.org/swift-6.3-release/windows10/swift-6.3-RELEASE/swift-6.3-RELEASE-windows10.exe'
    $SWIFT_SHA256='a1370df009de920070aef0c87d4ff80279515870ddbe6e8f035b2a5707444f13'
}

Install-Swift -Url $SWIFT -Sha256 $SWIFT_SHA256
